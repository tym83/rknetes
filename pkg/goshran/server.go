package goshran

import (
	"fmt"
	"net/http"
	"net/http/httputil"
	"net/url"
	"strings"
)

type Server struct {
	Upstream *url.URL
	Index    []byte
	Proxy    *httputil.ReverseProxy
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
	return &Server{Upstream: u, Index: index, Proxy: p}, nil
}
func (s *Server) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	switch {
	case r.URL.Path == "/healthz":
		w.WriteHeader(200)
	case r.URL.Path == "/metrics":
		fmt.Fprintln(w, "rknetes_domestic_download_ratio 1\nrknetes_availability_ratio 1")
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
