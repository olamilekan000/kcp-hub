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
// The UI only ever talks to its own origin, because kcp sends no CORS
// headers. With --upstream set, this server passes /services and /clusters
// on to kcp's front-proxy, carrying the user's own token and holding no
// credential of its own. Without it, something in front of the console has
// to route those paths.
package main

import (
	"crypto/tls"
	"crypto/x509"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io/fs"
	"log"
	"net/http"
	"net/http/httputil"
	"net/url"
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
	// KCPCA is the PEM bundle that signs KCPServer's certificate, so the
	// kubeconfig the UI hands out works without trusting anything else.
	KCPCA string `json:"kcpCA,omitempty"`
}

func main() {
	addr := flag.String("address", ":8080", "Address to listen on.")
	root := flag.String("root", "/www", "Directory holding the built UI.")
	upstream := flag.String("upstream", "", "kcp front-proxy URL to pass /services and /clusters on to.")
	upstreamCA := flag.String("upstream-ca-file", "", "CA bundle that signs the front-proxy's certificate.")
	tlsCert := flag.String("tls-cert-file", "", "Serve HTTPS with this certificate.")
	tlsKey := flag.String("tls-key-file", "", "Key for --tls-cert-file.")
	kcpCA := flag.String("kcp-ca-file", "", "CA bundle that signs CONSOLE_KCP_SERVER's certificate, for the kubeconfigs the UI hands out.")
	flag.Parse()

	s := settings{
		KCPServer:    os.Getenv("CONSOLE_KCP_SERVER"),
		OIDCIssuer:   os.Getenv("CONSOLE_OIDC_ISSUER"),
		OIDCClientID: os.Getenv("CONSOLE_OIDC_CLIENT_ID"),
		OIDCScopes:   os.Getenv("CONSOLE_OIDC_SCOPES"),
	}
	if *kcpCA != "" {
		pem, err := os.ReadFile(*kcpCA)
		if err != nil {
			log.Fatalf("read --kcp-ca-file: %v", err)
		}
		s.KCPCA = string(pem)
	}
	cfg, err := configJS(s)
	if err != nil {
		log.Fatal(err)
	}

	var api http.Handler
	if *upstream != "" {
		if api, err = apiProxy(*upstream, *upstreamCA); err != nil {
			log.Fatal(err)
		}
	}

	srv := &http.Server{
		Addr:              *addr,
		Handler:           handler(os.DirFS(*root), cfg, api),
		ReadHeaderTimeout: 10 * time.Second,
	}
	log.Printf("serving %s on %s", *root, *addr)
	if *tlsCert != "" {
		log.Fatal(srv.ListenAndServeTLS(*tlsCert, *tlsKey))
	}
	log.Fatal(srv.ListenAndServe())
}

// apiProxy passes requests on to kcp's front-proxy unchanged, including
// the caller's Authorization header, so kcp authorizes every request as
// the user who made it.
func apiProxy(upstream, caFile string) (http.Handler, error) {
	target, err := url.Parse(upstream)
	if err != nil || target.Scheme == "" || target.Host == "" {
		return nil, fmt.Errorf("--upstream must be a URL such as https://kcp.example.com:8443, got %q", upstream)
	}
	tlsConfig := &tls.Config{MinVersion: tls.VersionTLS12}
	if caFile != "" {
		pem, err := os.ReadFile(caFile)
		if err != nil {
			return nil, fmt.Errorf("read --upstream-ca-file: %w", err)
		}
		tlsConfig.RootCAs = x509.NewCertPool()
		if !tlsConfig.RootCAs.AppendCertsFromPEM(pem) {
			return nil, fmt.Errorf("--upstream-ca-file %s holds no PEM certificates", caFile)
		}
	}
	transport := http.DefaultTransport.(*http.Transport).Clone()
	transport.TLSClientConfig = tlsConfig
	return &httputil.ReverseProxy{
		Rewrite:   func(r *httputil.ProxyRequest) { r.SetURL(target) },
		Transport: transport,
	}, nil
}

func isAPIPath(p string) bool {
	return strings.HasPrefix(p, "/services/") || strings.HasPrefix(p, "/clusters/")
}

func configJS(s settings) ([]byte, error) {
	b, err := json.Marshal(s)
	if err != nil {
		return nil, fmt.Errorf("encode settings: %w", err)
	}
	return fmt.Appendf(nil, "window.__CONSOLE_CONFIG__ = %s\n", b), nil
}

// handler serves the UI, and passes API paths to api when it is set.
func handler(files fs.FS, cfg []byte, api http.Handler) http.Handler {
	static := http.FileServerFS(files)
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if api != nil && isAPIPath(r.URL.Path) {
			api.ServeHTTP(w, r)
			return
		}
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
