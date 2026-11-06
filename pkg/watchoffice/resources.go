package watchoffice

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"

	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/fields"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"rknetes.su/rknetes/pkg/cluster"
)

type subject struct{ Namespace, Resource, Name string }

func (o subject) key() string { return o.Namespace + "/" + o.Resource + "/" + o.Name }

type registration struct {
	Object          *cluster.Object
	Threshold, Peak int64
	Registered      bool
}

type registrationSnapshotKey struct{}

func (s *Server) registration(ctx context.Context, o subject) (registration, error) {
	result := registration{Threshold: 10000}
	items, cached := ctx.Value(registrationSnapshotKey{}).([]cluster.Object)
	if !cached {
		var err error
		items, err = s.C.List(ctx, "bloggerregistrations", o.Namespace)
		if err != nil {
			return result, err
		}
	}
	for i := range items {
		p := &items[i]
		if cluster.String(p.Object, "spec", "resource") == o.Resource && cluster.String(p.Object, "spec", "name") == o.Name {
			result.Object = p
			result.Threshold = cluster.Int(p.Object, 10000, "spec", "threshold")
			result.Peak = cluster.Int(p.Object, 0, "status", "observedConcurrentWatches")
			result.Registered = cluster.Bool(p.Object, "spec", "registered")
			break
		}
	}
	s.mu.Lock()
	result.Peak = max(result.Peak, s.peaks[o.key()])
	s.peaks[o.key()] = result.Peak
	s.mu.Unlock()
	return result, nil
}

func (s *Server) record(ctx context.Context, o subject, reg registration, blocked bool) error {
	s.persist.Lock()
	defer s.persist.Unlock()
	ctx, cancel := context.WithTimeout(context.WithoutCancel(ctx), 5*time.Second)
	defer cancel()
	s.mu.Lock()
	peak := max(reg.Peak, s.peaks[o.key()])
	s.mu.Unlock()
	if reg.Object == nil {
		digest := sha256.Sum256([]byte(o.key()))
		name := "blog-" + hex.EncodeToString(digest[:12])
		if o.Resource == "configmaps" {
			name = o.Name
		}
		reg.Object = cluster.NewObject("rknetes.su/v1alpha1", "BloggerRegistration", o.Namespace, name, cluster.Map{"resource": o.Resource, "name": o.Name, "registered": false, "threshold": reg.Threshold})
		if err := s.C.Apply(ctx, "bloggerregistrations", reg.Object); err != nil && !apierrors.IsAlreadyExists(err) {
			return err
		}
	}
	status, reason, message := "True", "Registered", "Registered channel reads are permitted"
	if blocked {
		status, reason, message = "False", "UnregisteredBlogger", "Registration remains required after watches close"
	}
	return s.C.Status(ctx, "bloggerregistrations", reg.Object, cluster.Map{"observedConcurrentWatches": peak, "conditions": []interface{}{cluster.Condition("ReadAllowed", status, reason, message)}})
}

type subscription struct {
	server *Server
	id     uint64
	cancel context.CancelFunc
	mu     chan struct{}
	closed bool
	keys   map[string]bool
}

func (s *Server) subscribe(cancel context.CancelFunc) *subscription {
	s.mu.Lock()
	s.next++
	id := s.next
	s.mu.Unlock()
	return &subscription{server: s, id: id, cancel: cancel, mu: make(chan struct{}, 1), keys: map[string]bool{}}
}
func (sub *subscription) add(ctx context.Context, o subject) (bool, error) {
	reg, err := sub.server.registration(ctx, o)
	if err != nil {
		return false, err
	}
	sub.mu <- struct{}{}
	defer func() { <-sub.mu }()
	if sub.closed {
		return false, context.Canceled
	}
	s := sub.server
	s.mu.Lock()
	if !sub.keys[o.key()] {
		if s.watches[o.key()] == nil {
			s.watches[o.key()] = map[uint64]context.CancelFunc{}
		}
		s.watches[o.key()][sub.id] = sub.cancel
		sub.keys[o.key()] = true
	}
	peak := max(reg.Peak, int64(len(s.watches[o.key()])))
	s.peaks[o.key()] = max(s.peaks[o.key()], peak)
	blocked := !reg.Registered && peak > reg.Threshold
	if blocked {
		for _, cancel := range s.watches[o.key()] {
			cancel()
		}
	}
	s.mu.Unlock()
	if blocked {
		if err := s.record(ctx, o, reg, true); err != nil {
			return false, err
		}
		return false, nil
	}
	return true, nil
}
func (sub *subscription) remove(o subject) {
	sub.mu <- struct{}{}
	defer func() { <-sub.mu }()
	sub.server.mu.Lock()
	defer sub.server.mu.Unlock()
	delete(sub.server.watches[o.key()], sub.id)
	delete(sub.keys, o.key())
	if len(sub.server.watches[o.key()]) == 0 {
		delete(sub.server.watches, o.key())
	}
}
func (sub *subscription) close() {
	sub.mu <- struct{}{}
	defer func() { <-sub.mu }()
	sub.closed = true
	sub.server.mu.Lock()
	defer sub.server.mu.Unlock()
	for key := range sub.keys {
		delete(sub.server.watches[key], sub.id)
		if len(sub.server.watches[key]) == 0 {
			delete(sub.server.watches, key)
		}
	}
}

func (s *Server) readAllowed(ctx context.Context, o subject) (bool, error) {
	reg, err := s.registration(ctx, o)
	if err != nil {
		return false, err
	}
	if !reg.Registered && reg.Peak > reg.Threshold {
		return false, nil
	}
	if reg.Registered && reg.Object != nil {
		status, _ := reg.Object.Object["status"].(map[string]interface{})
		conditions, _ := status["conditions"].([]interface{})
		for _, item := range conditions {
			c := item.(map[string]interface{})
			if c["type"] == "ReadAllowed" && c["status"] == "False" {
				if err := s.record(ctx, o, reg, false); err != nil {
					return false, err
				}
				break
			}
		}
	}
	return true, nil
}

func (s *Server) serveResource(w http.ResponseWriter, r *http.Request) {
	m := resourcePath.FindStringSubmatch(r.URL.Path)
	if r.Method != "GET" || m == nil {
		http.Error(w, "a namespaced resource read or watch is required", 400)
		return
	}
	watch := r.URL.Query().Get("watch") == "true"
	if watch && m[7] != "" {
		http.Error(w, "watch a collection with selectors", 400)
		return
	}
	gvr := schema.GroupVersionResource{Group: m[3], Version: m[4], Resource: m[6]}
	if gvr.Group == "" {
		gvr.Version = m[2]
	}
	qualified := gvr.Resource
	if gvr.Group != "" {
		qualified += "." + gvr.Group
	}
	ns, err := s.C.R("namespaces", "").Get(r.Context(), m[5], metav1.GetOptions{})
	if err != nil || ns.GetLabels()["rknetes.su/lab"] != "true" {
		http.Error(w, "lab namespace required", 403)
		return
	}
	selector, err := fields.ParseSelector(r.URL.Query().Get("fieldSelector"))
	if err != nil {
		http.Error(w, "invalid field selector", 400)
		return
	}
	selectedName, _ := selector.RequiresExactMatch("metadata.name")
	name := m[7]
	if name == "" {
		name = selectedName
	}
	verb := "list"
	if watch {
		verb = "watch"
	} else if m[7] != "" {
		verb = "get"
	}
	cert := r.TLS.VerifiedChains[0][0]
	groups := []interface{}{}
	for _, group := range cert.Subject.Organization {
		groups = append(groups, group)
	}
	sar := cluster.NewObject("authorization.k8s.io/v1", "SubjectAccessReview", "", "", cluster.Map{"user": cert.Subject.CommonName, "groups": groups, "resourceAttributes": cluster.Map{"namespace": m[5], "verb": verb, "group": gvr.Group, "resource": gvr.Resource, "name": name}})
	delete(sar.Object, "metadata")
	result, err := s.C.Dynamic.Resource(schema.GroupVersionResource{Group: "authorization.k8s.io", Version: "v1", Resource: "subjectaccessreviews"}).Create(r.Context(), sar, metav1.CreateOptions{})
	if err != nil || !cluster.Bool(result.Object, "status", "allowed") {
		http.Error(w, "resource read forbidden", 403)
		return
	}
	eventContext := r.Context()
	registrations, err := s.C.List(r.Context(), "bloggerregistrations", m[5])
	if err != nil {
		http.Error(w, err.Error(), 503)
		return
	}
	r = r.WithContext(context.WithValue(r.Context(), registrationSnapshotKey{}, registrations))
	objects := []subject{}
	if name != "" {
		objects = append(objects, subject{m[5], qualified, name})
		allowed, err := s.readAllowed(r.Context(), objects[0])
		if err != nil {
			http.Error(w, err.Error(), 503)
			return
		}
		if !allowed {
			http.Error(w, "UnavailableForLegalReasons: registration required", 451)
			return
		}
	}
	if m[7] == "" {
		// A real list verifies the resource route and resolves collection selectors.
		list, err := s.C.Dynamic.Resource(gvr).Namespace(m[5]).List(r.Context(), metav1.ListOptions{LabelSelector: r.URL.Query().Get("labelSelector"), FieldSelector: r.URL.Query().Get("fieldSelector")})
		if err != nil {
			http.Error(w, err.Error(), 503)
			return
		}
		if name == "" {
			for _, object := range list.Items {
				objects = append(objects, subject{m[5], qualified, object.GetName()})
			}
		}
	}
	for _, object := range objects {
		allowed, err := s.readAllowed(r.Context(), object)
		if err != nil {
			http.Error(w, err.Error(), 503)
			return
		}
		if !allowed {
			http.Error(w, "UnavailableForLegalReasons: collection includes an unregistered channel", 451)
			return
		}
	}
	if !watch {
		s.Proxy.ServeHTTP(w, r)
		return
	}
	ctx, cancel := context.WithCancel(r.Context())
	defer cancel()
	sub := s.subscribe(cancel)
	defer sub.close()
	for _, object := range objects {
		allowed, err := sub.add(r.Context(), object)
		if err != nil {
			http.Error(w, err.Error(), 503)
			return
		}
		if !allowed {
			http.Error(w, "UnavailableForLegalReasons: observed audience exceeds threshold", 451)
			return
		}
	}
	proxy := *s.Proxy
	if name == "" {
		proxy.ModifyResponse = func(response *http.Response) error {
			if response.StatusCode == 200 {
				response.Body = observeBody(response.Body, sub, eventContext, m[5], qualified)
			}
			return nil
		}
	}
	proxy.ServeHTTP(w, r.WithContext(ctx))
}

type observedBody struct {
	io.ReadCloser
	source io.ReadCloser
}

func (b *observedBody) Close() error { b.source.Close(); return b.ReadCloser.Close() }
func observeBody(source io.ReadCloser, sub *subscription, ctx context.Context, ns, resource string) io.ReadCloser {
	reader, writer := io.Pipe()
	go func() {
		defer source.Close()
		defer writer.Close()
		decoder := json.NewDecoder(source)
		for {
			var raw json.RawMessage
			if err := decoder.Decode(&raw); err != nil {
				if err != io.EOF {
					writer.CloseWithError(err)
				}
				return
			}
			var event struct {
				Type   string `json:"type"`
				Object struct {
					Metadata struct {
						Name string `json:"name"`
					} `json:"metadata"`
				} `json:"object"`
			}
			if json.Unmarshal(raw, &event) != nil {
				return
			}
			if event.Object.Metadata.Name != "" {
				o := subject{ns, resource, event.Object.Metadata.Name}
				switch event.Type {
				case "ADDED", "MODIFIED":
					allowed, err := sub.add(ctx, o)
					if err != nil || !allowed {
						writer.CloseWithError(fmt.Errorf("channel registration required"))
						return
					}
				case "DELETED":
					sub.remove(o)
				}
			}
			if _, err := writer.Write(append(raw, '\n')); err != nil {
				return
			}
		}
	}()
	return &observedBody{ReadCloser: reader, source: source}
}
