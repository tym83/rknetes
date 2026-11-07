// Package watchoffice counts real, concurrent object watches through a lab gateway.
package watchoffice

import (
	"context"
	"k8s.io/client-go/rest"
	"net/http"
	"net/http/httputil"
	"net/url"
	"regexp"
	"rknetes.su/rknetes/pkg/cluster"
	"strings"
	"sync"
)

var resourcePath = regexp.MustCompile(`^/(api/([a-z0-9]+)|apis/([a-z0-9.-]+)/([a-z0-9]+))/namespaces/([a-z0-9-]+)/([a-z0-9-]+)(?:/([a-z0-9.-]+))?$`)
var discoveryPath = regexp.MustCompile(`^(/api(/v1)?|/apis(/[a-z0-9.-]+(/[a-zA-Z0-9]+)?)?|/version|/openapi/(v2|v3)(/apis/[a-z0-9.-]+/[a-zA-Z0-9]+)?)$`)

type Server struct {
	C       *cluster.Client
	Proxy   *httputil.ReverseProxy
	mu      sync.Mutex
	persist sync.Mutex
	next    uint64
	watches map[string]map[uint64]context.CancelFunc
	peaks   map[string]int64
}

func New(c *cluster.Client) (*Server, error) {
	u, err := url.Parse(c.Config.Host)
	if err != nil {
		return nil, err
	}
	transport, err := rest.TransportFor(c.Config)
	if err != nil {
		return nil, err
	}
	p := httputil.NewSingleHostReverseProxy(u)
	p.Transport = transport
	p.FlushInterval = -1
	old := p.Director
	p.Director = func(r *http.Request) {
		old(r)
		r.Host = u.Host
		r.Header.Del("Authorization")
		for key := range r.Header {
			if strings.HasPrefix(strings.ToLower(key), "impersonate-") {
				r.Header.Del(key)
			}
		}
		r.Header.Set("Accept", "application/json")
	}
	return &Server{C: c, Proxy: p, watches: map[string]map[uint64]context.CancelFunc{}, peaks: map[string]int64{}}, nil
}
func (s *Server) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if r.TLS == nil || len(r.TLS.VerifiedChains) == 0 {
		http.Error(w, "client certificate required", 401)
		return
	}
	if r.Method == "GET" && discoveryPath.MatchString(r.URL.Path) {
		s.Proxy.ServeHTTP(w, r)
		return
	}
	s.serveResource(w, r)
}
