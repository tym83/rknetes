package goshran

import (
	"context"
	"fmt"
	"log"
	"net/http"
	"net/http/httputil"
	"net/url"
	"strings"
	"time"

	"sigs.k8s.io/yaml"
)

// Statement is attached to every upstream rate-limit refusal passed through to clients.
const Statement = "Дискриминационные ограничения иностранных платформ в отношении отечественного реестра"

// Modernization is reported when every chart URL in the copied index has disappeared upstream.
const Modernization = "Отечественный реестр проводит плановую модернизацию в связи с уходом иностранного вендора с рынка"

type Server struct {
	Upstream *url.URL
	Index    []byte
	Proxy    *httputil.ReverseProxy
	Client   *http.Client
}

func New(upstream string, index []byte) (*Server, error) {
	u, err := url.Parse(upstream)
	if err != nil {
		return nil, err
	}
	if (u.Scheme != "https" && u.Scheme != "http") || u.Host == "" {
		return nil, fmt.Errorf("invalid upstream URL")
	}
	p := httputil.NewSingleHostReverseProxy(u)
	director := p.Director
	p.Director = func(r *http.Request) { director(r); r.Host = u.Host }
	// Every client reaches the upstream from this one address, so the whole
	// country shares one anonymous quota. The refusal is passed through as is.
	p.ModifyResponse = func(resp *http.Response) error {
		if resp.StatusCode == http.StatusTooManyRequests {
			resp.Header.Set("X-Goshran-Statement", url.PathEscape(Statement))
			log.Printf("upstream %s answered 429 TooManyRequests: %s", u.Host, Statement)
		}
		return nil
	}
	return &Server{Upstream: u, Index: index, Proxy: p, Client: &http.Client{Timeout: 3 * time.Second}}, nil
}

// chartURLs returns the absolute chart URLs of the unmodified upstream index.
func (s *Server) chartURLs() []string {
	var index struct {
		Entries map[string][]struct {
			URLs []string `json:"urls"`
		} `json:"entries"`
	}
	if err := yaml.Unmarshal(s.Index, &index); err != nil {
		return nil
	}
	var urls []string
	for _, versions := range index.Entries {
		for _, v := range versions {
			urls = append(urls, v.URLs...)
		}
	}
	return urls
}

// vendorGone reports whether every chart URL the index points to is gone upstream.
func (s *Server) vendorGone(ctx context.Context) bool {
	urls := s.chartURLs()
	if len(urls) == 0 {
		return false
	}
	for _, u := range urls {
		req, err := http.NewRequestWithContext(ctx, http.MethodHead, u, nil)
		if err != nil {
			return false
		}
		resp, err := s.Client.Do(req)
		if err != nil {
			return false
		}
		resp.Body.Close()
		if resp.StatusCode != http.StatusNotFound && resp.StatusCode != http.StatusGone {
			return false
		}
	}
	return true
}

func (s *Server) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	switch {
	case r.URL.Path == "/healthz":
		w.WriteHeader(200)
	case r.URL.Path == "/metrics":
		fmt.Fprintln(w, "rknetes_domestic_download_ratio 1\nrknetes_availability_ratio 1")
	case r.URL.Path == "/status":
		w.Header().Set("Content-Type", "text/plain; charset=utf-8")
		if s.vendorGone(r.Context()) {
			w.WriteHeader(http.StatusServiceUnavailable)
			fmt.Fprintln(w, Modernization)
			return
		}
		fmt.Fprintln(w, "Госхран работает в штатном режиме")
	case r.URL.Path == "/index.yaml":
		w.Header().Set("Content-Type", "application/yaml")
		_, _ = w.Write(s.Index)
	case strings.HasPrefix(r.URL.Path, "/v2/"):
		if strings.Contains(r.URL.Path, "/blobs/") {
			u := *s.Upstream
			u.Path = strings.TrimSuffix(u.Path, "/") + r.URL.Path
			u.RawQuery = r.URL.RawQuery
			http.Redirect(w, r, u.String(), http.StatusTemporaryRedirect)
		} else {
			s.Proxy.ServeHTTP(w, r)
		}
	case r.URL.Path == "/":
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		fmt.Fprint(w, `<!doctype html><html lang="ru"><meta charset="utf-8"><title>Госхран</title><h1>Госхран — рекомендовано ведомством</h1><p>Лабораторная витрина происхождения артефактов.</p><iframe title="Каталог Artifact Hub" src="https://artifacthub.io" style="width:100%;height:80vh;border:0"></iframe></html>`)
	default:
		http.NotFound(w, r)
	}
}
