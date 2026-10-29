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

// Command console serves the built web UI. It exists so one image works
// for every deployment: the settings a build would otherwise bake in are
// read from the environment at startup and served as /config.js.
//
// The UI only ever talks to its own origin, so the console is meant to sit
// behind the same address as kcp's front-proxy, with /services and
// /clusters routed to the front-proxy and everything else here.
package main

import (
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io/fs"
	"log"
	"net/http"
	"os"
	"path"
	"strings"
	"time"
)

// settings mirrors ui/src/lib/settings.ts.
type settings struct {
	KCPServer    string `json:"kcpServer,omitempty"`
	OIDCIssuer   string `json:"oidcIssuer,omitempty"`
	OIDCClientID string `json:"oidcClientId,omitempty"`
	OIDCScopes   string `json:"oidcScopes,omitempty"`
}

func main() {
	addr := flag.String("address", ":8080", "Address to listen on.")
	root := flag.String("root", "/www", "Directory holding the built UI.")
	flag.Parse()

	cfg, err := configJS(settings{
		KCPServer:    os.Getenv("CONSOLE_KCP_SERVER"),
		OIDCIssuer:   os.Getenv("CONSOLE_OIDC_ISSUER"),
		OIDCClientID: os.Getenv("CONSOLE_OIDC_CLIENT_ID"),
		OIDCScopes:   os.Getenv("CONSOLE_OIDC_SCOPES"),
	})
	if err != nil {
		log.Fatal(err)
	}

	srv := &http.Server{
		Addr:              *addr,
		Handler:           handler(os.DirFS(*root), cfg),
		ReadHeaderTimeout: 10 * time.Second,
	}
	log.Printf("serving %s on %s", *root, *addr)
	log.Fatal(srv.ListenAndServe())
}

func configJS(s settings) ([]byte, error) {
	b, err := json.Marshal(s)
	if err != nil {
		return nil, fmt.Errorf("encode settings: %w", err)
	}
	return fmt.Appendf(nil, "window.__CONSOLE_CONFIG__ = %s\n", b), nil
}

func handler(files fs.FS, cfg []byte) http.Handler {
	static := http.FileServerFS(files)
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("X-Content-Type-Options", "nosniff")

		switch {
		case r.URL.Path == "/healthz":
			_, _ = w.Write([]byte("ok"))
			return
		case r.URL.Path == "/config.js":
			w.Header().Set("Content-Type", "text/javascript; charset=utf-8")
			w.Header().Set("Cache-Control", "no-store")
			_, _ = w.Write(cfg)
			return
		case strings.HasPrefix(r.URL.Path, "/assets/"):
			// Vite puts a content hash in every asset name.
			w.Header().Set("Cache-Control", "public, max-age=31536000, immutable")
			static.ServeHTTP(w, r)
			return
		}

		name := strings.TrimPrefix(path.Clean(r.URL.Path), "/")
		if name != "" {
			if _, err := fs.Stat(files, name); err == nil {
				static.ServeHTTP(w, r)
				return
			} else if !errors.Is(err, fs.ErrNotExist) {
				http.Error(w, err.Error(), http.StatusInternalServerError)
				return
			}
		}

		// Client-side routes such as /callback or /catalog have no file of
		// their own; the app resolves them once index.html has loaded.
		w.Header().Set("Cache-Control", "no-cache")
		http.ServeFileFS(w, r, files, "index.html")
	})
}
