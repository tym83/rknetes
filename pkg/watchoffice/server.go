// Package watchoffice counts real, concurrent object watches through a lab gateway.
package watchoffice

import (
	"context"
	"fmt"
	"net/http"
	"net/http/httputil"
	"net/url"
	"regexp"
	"strings"
	"sync"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"k8s.io/client-go/rest"
	"rknetes.su/rknetes/pkg/cluster"
)

var path = regexp.MustCompile(`^/api/v1/namespaces/([a-z0-9-]+)/configmaps$`)

type Server struct {
	C       *cluster.Client
	Proxy   *httputil.ReverseProxy
	mu      sync.Mutex
	next    uint64
	watches map[string]map[uint64]context.CancelFunc
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
	}
	return &Server{C: c, Proxy: p, watches: map[string]map[uint64]context.CancelFunc{}}, nil
}
func (s *Server) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if r.TLS == nil || len(r.TLS.VerifiedChains) == 0 {
		http.Error(w, "client certificate required", 401)
		return
	}
	m := path.FindStringSubmatch(r.URL.Path)
	name := strings.TrimPrefix(r.URL.Query().Get("fieldSelector"), "metadata.name=")
	if r.Method != "GET" || m == nil || r.URL.Query().Get("watch") != "true" || !strings.HasPrefix(r.URL.Query().Get("fieldSelector"), "metadata.name=") || name == "" || strings.ContainsAny(name, "=,/") {
		http.Error(w, "an individual ConfigMap watch with metadata.name is required", 400)
		return
	}
	ns, err := s.C.R("namespaces", "").Get(r.Context(), m[1], metav1.GetOptions{})
	if err != nil || ns.GetLabels()["rknetes.su/lab"] != "true" {
		http.Error(w, "lab namespace required", 403)
		return
	}
	cert := r.TLS.VerifiedChains[0][0]
	groups := []interface{}{}
	for _, g := range cert.Subject.Organization {
		groups = append(groups, g)
	}
	sar := &unstructured.Unstructured{Object: cluster.Map{"apiVersion": "authorization.k8s.io/v1", "kind": "SubjectAccessReview", "spec": cluster.Map{"user": cert.Subject.CommonName, "groups": groups, "resourceAttributes": cluster.Map{"namespace": m[1], "verb": "watch", "resource": "configmaps", "name": name}}}}
	result, err := s.C.Dynamic.Resource(schema.GroupVersionResource{Group: "authorization.k8s.io", Version: "v1", Resource: "subjectaccessreviews"}).Create(r.Context(), sar, metav1.CreateOptions{})
	if err != nil || !cluster.Bool(result.Object, "status", "allowed") {
		http.Error(w, "watch forbidden", 403)
		return
	}
	registrations, err := s.C.List(r.Context(), "bloggerregistrations", m[1])
	if err != nil {
		http.Error(w, err.Error(), 503)
		return
	}
	var registration *cluster.Object
	threshold := int64(10000)
	registered := false
	for i := range registrations {
		p := &registrations[i]
		if cluster.String(p.Object, "spec", "resource") == "configmaps" && cluster.String(p.Object, "spec", "name") == name {
			registration = p
			threshold = cluster.Int(p.Object, 10000, "spec", "threshold")
			registered = cluster.Bool(p.Object, "spec", "registered")
			break
		}
	}
	key := m[1] + "/" + name
	ctx, cancel := context.WithCancel(r.Context())
	defer cancel()
	s.mu.Lock()
	if s.watches[key] == nil {
		s.watches[key] = map[uint64]context.CancelFunc{}
	}
	s.next++
	id := s.next
	s.watches[key][id] = cancel
	count := len(s.watches[key])
	blocked := !registered && int64(count) > threshold
	if blocked {
		for _, stop := range s.watches[key] {
			stop()
		}
	}
	s.mu.Unlock()
	defer func() {
		s.mu.Lock()
		delete(s.watches[key], id)
		if len(s.watches[key]) == 0 {
			delete(s.watches, key)
		}
		s.mu.Unlock()
	}()
	if blocked {
		if registration == nil {
			registration = cluster.NewObject("rknetes.su/v1alpha1", "BloggerRegistration", m[1], name, cluster.Map{"resource": "configmaps", "name": name, "registered": false, "threshold": threshold})
			if err := s.C.Apply(r.Context(), "bloggerregistrations", registration); err != nil {
				http.Error(w, err.Error(), 503)
				return
			}
		}
		if err := s.C.Status(r.Context(), "bloggerregistrations", registration, cluster.Map{"observedConcurrentWatches": int64(count), "conditions": []interface{}{cluster.Condition("ReadAllowed", "False", "UnregisteredBlogger", "Active watches closed after the registration threshold was exceeded")}}); err != nil {
			http.Error(w, err.Error(), 503)
			return
		}
		http.Error(w, fmt.Sprintf("UnavailableForLegalReasons: %d active watches exceed %d; registration required", count, threshold), 451)
		return
	}
	s.Proxy.ServeHTTP(w, r.WithContext(ctx))
}
