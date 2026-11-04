package maxlet

import (
	"bufio"
	"bytes"
	"context"
	"crypto/tls"
	"crypto/x509"
	"encoding/json"
	"fmt"
	"io"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"k8s.io/client-go/rest"
	"net"
	"net/http"
	"net/http/httputil"
	"net/url"
	"os"
	"path/filepath"
	"regexp"
	"rknetes.su/rknetes/pkg/cluster"
	"strings"
	"sync"
	"time"
)

var callPath = regexp.MustCompile(`^/api/v1/namespaces/([a-z0-9-]+)/pods/([a-z0-9.-]+)(?:/(exec|attach|portforward))?$`)

type Server struct {
	C       *cluster.Client
	Proxy   *httputil.ReverseProxy
	Archive string
}

func New(c *cluster.Client, archive string) (*Server, error) {
	endpoint, err := url.Parse(c.Config.Host)
	if err != nil {
		return nil, err
	}
	transport, err := rest.TransportFor(c.Config)
	if err != nil {
		return nil, err
	}
	proxy := httputil.NewSingleHostReverseProxy(endpoint)
	proxy.Transport = transport
	director := proxy.Director
	proxy.Director = func(r *http.Request) {
		director(r)
		r.Host = endpoint.Host
		r.Header.Del("Authorization")
		r.Header.Del("Impersonate-User")
		r.Header.Del("Impersonate-Group")
	}
	return &Server{C: c, Proxy: proxy, Archive: archive}, os.MkdirAll(archive, 0700)
}
func (s *Server) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if r.TLS == nil || len(r.TLS.VerifiedChains) == 0 {
		http.Error(w, "verified client certificate required", 401)
		return
	}
	match := callPath.FindStringSubmatch(r.URL.Path)
	if match == nil {
		if r.Method == "GET" && (r.URL.Path == "/api" || r.URL.Path == "/apis" || r.URL.Path == "/api/v1" || r.URL.Path == "/version" || strings.HasPrefix(r.URL.Path, "/apis/") || strings.HasPrefix(r.URL.Path, "/openapi/")) {
			s.Proxy.ServeHTTP(w, r)
			return
		}
		http.Error(w, "MAX carries pod calls only", 404)
		return
	}
	ns, err := s.C.R("namespaces", "").Get(r.Context(), match[1], metav1.GetOptions{})
	if err != nil || ns.GetLabels()["rknetes.su/lab"] != "true" {
		http.Error(w, "lab namespace required", 403)
		return
	}
	cert := r.TLS.VerifiedChains[0][0]
	verb := "create"
	if match[3] == "" {
		if r.Method != "GET" {
			http.Error(w, "read or call required", 405)
			return
		}
		verb = "get"
	}
	review := &unstructured.Unstructured{Object: cluster.Map{"apiVersion": "authorization.k8s.io/v1", "kind": "SubjectAccessReview", "spec": cluster.Map{"user": cert.Subject.CommonName, "groups": toAny(cert.Subject.Organization), "resourceAttributes": cluster.Map{"namespace": match[1], "verb": verb, "group": "", "resource": "pods", "subresource": match[3], "name": match[2]}}}}
	result, err := s.C.Dynamic.Resource(schema.GroupVersionResource{Group: "authorization.k8s.io", Version: "v1", Resource: "subjectaccessreviews"}).Create(r.Context(), review, metav1.CreateOptions{})
	if err != nil || !cluster.Bool(result.Object, "status", "allowed") {
		http.Error(w, "caller is not authorized for this pod call", 403)
		return
	}
	file, err := os.CreateTemp(s.Archive, "call-*.jsonl")
	if err != nil {
		http.Error(w, "archive unavailable", 503)
		return
	}
	defer file.Close()
	recorder := &record{enc: json.NewEncoder(file)}
	recorder.write("request", []byte(cert.Subject.CommonName+" "+r.URL.Path))
	s.Proxy.ServeHTTP(&writer{ResponseWriter: w, rec: recorder}, r)
}
func toAny(values []string) []interface{} {
	out := make([]interface{}, len(values))
	for i, v := range values {
		out[i] = v
	}
	return out
}

type record struct {
	mu  sync.Mutex
	enc *json.Encoder
}

func (r *record) write(direction string, b []byte) {
	r.mu.Lock()
	defer r.mu.Unlock()
	_ = r.enc.Encode(map[string]interface{}{"time": time.Now().UTC(), "direction": direction, "bytes": b})
}

type connection struct {
	net.Conn
	rec *record
}

func (c *connection) Read(b []byte) (int, error) {
	n, e := c.Conn.Read(b)
	if n > 0 {
		c.rec.write("client", b[:n])
	}
	return n, e
}
func (c *connection) Write(b []byte) (int, error) {
	n, e := c.Conn.Write(b)
	if n > 0 {
		c.rec.write("server", b[:n])
	}
	return n, e
}

type writer struct {
	http.ResponseWriter
	rec *record
}

func (w *writer) Hijack() (net.Conn, *bufio.ReadWriter, error) {
	h, ok := w.ResponseWriter.(http.Hijacker)
	if !ok {
		return nil, nil, fmt.Errorf("stream hijacking unavailable")
	}
	conn, buffer, err := h.Hijack()
	if err != nil {
		return nil, nil, err
	}
	// Keep already buffered client bytes; future reads and writes are recorded.
	recorded := &connection{Conn: conn, rec: w.rec}
	reader := bufio.NewReader(recorded)
	if n := buffer.Reader.Buffered(); n > 0 {
		pending := make([]byte, n)
		if _, err := io.ReadFull(buffer.Reader, pending); err != nil {
			return nil, nil, err
		}
		w.rec.write("client", pending)
		reader = bufio.NewReader(io.MultiReader(bytes.NewReader(pending), recorded))
	}
	return recorded, bufio.NewReadWriter(reader, bufio.NewWriter(recorded)), nil
}
func (w *writer) Flush() {
	if f, ok := w.ResponseWriter.(http.Flusher); ok {
		f.Flush()
	}
}
func (w *writer) Write(b []byte) (int, error) {
	n, e := w.ResponseWriter.Write(b)
	if n > 0 {
		w.rec.write("server", b[:n])
	}
	return n, e
}
func Serve(ctx context.Context, c *cluster.Client, listen, cert, key, clientCA, archive string) error {
	handler, err := New(c, filepath.Clean(archive))
	if err != nil {
		return err
	}
	return ServeHandler(ctx, c, listen, cert, key, clientCA, handler)
}
func ServeHandler(ctx context.Context, c *cluster.Client, listen, cert, key, clientCA string, handler http.Handler) error {
	if err := c.Guard(ctx); err != nil {
		return err
	}
	data, err := os.ReadFile(clientCA)
	if err != nil {
		return err
	}
	pool := x509.NewCertPool()
	if !pool.AppendCertsFromPEM(data) {
		return fmt.Errorf("empty client CA")
	}
	server := &http.Server{Addr: listen, Handler: handler, ReadHeaderTimeout: 10 * time.Second, TLSConfig: &tls.Config{MinVersion: tls.VersionTLS12, ClientAuth: tls.RequireAndVerifyClientCert, ClientCAs: pool}}
	go func() { <-ctx.Done(); _ = server.Close() }()
	return server.ListenAndServeTLS(cert, key)
}
