/*
Copyright 2026 The kcp Authors.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

package main

import (
	"encoding/pem"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"testing/fstest"
)

func TestHandler(t *testing.T) {
	files := fstest.MapFS{
		"index.html":          {Data: []byte("<html>app</html>")},
		"config.js":           {Data: []byte("window.__CONSOLE_CONFIG__ = {}\n")},
		"assets/index-abc.js": {Data: []byte("console.log(1)")},
		"favicon.svg":         {Data: []byte("<svg/>")},
	}
	cfg, err := configJS(settings{OIDCIssuer: "https://dex.example.com/dex", OIDCClientID: "kcp"})
	if err != nil {
		t.Fatal(err)
	}
	h := handler(files, cfg, nil)

	tests := []struct {
		name, path   string
		wantBody     string
		wantCache    string
		wantContains bool
	}{
		{"settings come from the environment, not the file", "/config.js",
			`"oidcIssuer":"https://dex.example.com/dex"`, "no-store", true},
		{"hashed assets are cached for good", "/assets/index-abc.js",
			"console.log(1)", "public, max-age=31536000, immutable", false},
		{"other files are served as they are", "/favicon.svg", "<svg/>", "", false},
		{"client-side routes get the app", "/catalog", "<html>app</html>", "no-cache", false},
		{"the OIDC callback gets the app", "/callback", "<html>app</html>", "no-cache", false},
		{"the root gets the app", "/", "<html>app</html>", "no-cache", false},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			rec := httptest.NewRecorder()
			h.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, tt.path, nil))

			if rec.Code != http.StatusOK {
				t.Fatalf("status = %d, want 200", rec.Code)
			}
			body, _ := io.ReadAll(rec.Body)
			if tt.wantContains {
				if !strings.Contains(string(body), tt.wantBody) {
					t.Errorf("body = %q, want it to contain %q", body, tt.wantBody)
				}
			} else if string(body) != tt.wantBody {
				t.Errorf("body = %q, want %q", body, tt.wantBody)
			}
			if got := rec.Header().Get("Cache-Control"); got != tt.wantCache {
				t.Errorf("Cache-Control = %q, want %q", got, tt.wantCache)
			}
		})
	}
}

func TestAPIProxy(t *testing.T) {
	kcp := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, _ = io.WriteString(w, r.Method+" "+r.URL.RequestURI()+" "+r.Header.Get("Authorization"))
	}))
	defer kcp.Close()

	caFile := filepath.Join(t.TempDir(), "ca.crt")
	ca := pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: kcp.Certificate().Raw})
	if err := os.WriteFile(caFile, ca, 0o600); err != nil {
		t.Fatal(err)
	}
	api, err := apiProxy(kcp.URL, caFile)
	if err != nil {
		t.Fatal(err)
	}
	h := handler(fstest.MapFS{"index.html": {Data: []byte("<html>app</html>")}}, nil, api)

	tests := []struct {
		name, path, want string
	}{
		{"virtual workspaces go to kcp", "/services/tenancy/apis?watch=1",
			"POST /services/tenancy/apis?watch=1 Bearer user-token"},
		{"workspaces go to kcp", "/clusters/root:abc/api/v1",
			"POST /clusters/root:abc/api/v1 Bearer user-token"},
		{"everything else is the app", "/services", "<html>app</html>"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			req := httptest.NewRequest(http.MethodPost, tt.path, nil)
			req.Header.Set("Authorization", "Bearer user-token")
			rec := httptest.NewRecorder()
			h.ServeHTTP(rec, req)
			if body := rec.Body.String(); body != tt.want {
				t.Errorf("body = %q (status %d), want %q", body, rec.Code, tt.want)
			}
		})
	}
}

func TestAPIProxyRejectsABadUpstream(t *testing.T) {
	if _, err := apiProxy("kcp.example.com", ""); err == nil {
		t.Error("an upstream without a scheme was accepted")
	}
}

func TestConfigJSEscapes(t *testing.T) {
	cfg, err := configJS(settings{OIDCIssuer: `</script><script>alert(1)</script>`})
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(string(cfg), "</script>") {
		t.Errorf("config.js = %q, must not contain a raw </script>", cfg)
	}
}
