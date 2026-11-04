// Package presentation exposes the regulator's explicitly filtered public view.
// The native Kubernetes API remains observable and keeps its JSON contract.
package presentation

import (
	"bufio"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"regexp"
	"strings"
	"time"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"k8s.io/client-go/rest"
	"rknetes.su/rknetes/pkg/cluster"
)

const Disclaimer = "ДАННЫЙ МАТЕРИАЛ СОЗДАН И РАСПРОСТРАНЕН ИНОСТРАННЫМ АГЕНТОМ ИЛИ КАСАЕТСЯ ЕГО ДЕЯТЕЛЬНОСТИ В ЛАБОРАТОРНОМ КЛАСТЕРЕ РКНЕТЕС ЧИТАТЕЛЬ ОБЯЗАН ЗАМЕТИТЬ ЭТО УВЕДОМЛЕНИЕ ПЕРЕД КАЖДОЙ СТРОКОЙ СООБЩЕНИЯ"

var resourcePath = regexp.MustCompile(`^/(api/v1|apis/rknetes.su/v1alpha1)/namespaces/([a-z0-9-]+)/(pods|tunnelprofiles)(?:/([a-z0-9.-]+))?(?:/(log))?$`)
var forbidden = regexp.MustCompile(`(?i)\b(vpn|openvpn|wireguard|shadowsocks|vless|telegram)\b`)

func Banner() string {
	var b strings.Builder
	for _, r := range Disclaimer {
		b.WriteRune(r)
		b.WriteRune(r)
	}
	return b.String()
}

// Decorate records measured output bytes, including the duplicated Unicode text.
func Decorate(dst io.Writer, src io.Reader, redact bool) (int64, error) {
	scan := bufio.NewScanner(src)
	scan.Buffer(make([]byte, 4096), 4<<20)
	var total int64
	for scan.Scan() {
		line := scan.Text()
		if redact {
			line = forbidden.ReplaceAllString(line, "[ДАННЫЕ УДАЛЕНЫ]")
		}
		n, err := fmt.Fprintf(dst, "%s\n%s\n", Banner(), line)
		total += int64(n)
		if err != nil {
			return total, err
		}
	}
	return total, scan.Err()
}

type Server struct {
	C         *cluster.Client
	Namespace string
	HTTP      *http.Client
	Endpoint  *url.URL
}

func New(c *cluster.Client, ns string) (*Server, error) {
	endpoint, err := url.Parse(c.Config.Host)
	if err != nil {
		return nil, err
	}
	transport, err := rest.TransportFor(c.Config)
	if err != nil {
		return nil, err
	}
	return &Server{C: c, Namespace: ns, Endpoint: endpoint, HTTP: &http.Client{Transport: transport, Timeout: 30 * time.Second}}, nil
}

func (s *Server) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if r.TLS == nil || len(r.TLS.VerifiedChains) == 0 {
		http.Error(w, "verified client certificate required", 401)
		return
	}
	ns, err := s.C.R("namespaces", "").Get(r.Context(), s.Namespace, metav1.GetOptions{})
	if err != nil || ns.GetLabels()["rknetes.su/lab"] != "true" {
		http.Error(w, "lab namespace required", 403)
		return
	}
	policy, err := s.C.R("configmaps", s.Namespace).Get(r.Context(), "presentation-policy", metav1.GetOptions{})
	if err != nil {
		http.Error(w, "presentation policy unavailable", 503)
		return
	}
	// This is an explicit destructive gateway profile, never a native API patch.
	if cluster.String(policy.Object, "data", "mode") == "destructive" {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(451)
		_ = json.NewEncoder(w).Encode(cluster.Map{"apiVersion": "v1", "kind": "Status", "status": "Failure", "reason": "UnavailableForLegalReasons", "message": "Сведения не подлежат разглашению", "code": 451})
		return
	}
	m := resourcePath.FindStringSubmatch(r.URL.Path)
	if r.Method != "GET" || m == nil || m[2] != s.Namespace || r.URL.Query().Get("watch") != "" || r.URL.Query().Get("follow") == "true" {
		http.Error(w, "a bounded read in the selected lab namespace is required", 400)
		return
	}
	group := ""
	if m[1] != "api/v1" {
		group = "rknetes.su"
	}
	if (m[3] == "tunnelprofiles") != (group == "rknetes.su") || (m[5] != "" && (m[3] != "pods" || m[4] == "")) {
		http.Error(w, "unknown resource path", 404)
		return
	}
	verb := "get"
	if m[4] == "" {
		verb = "list"
	}
	cert := r.TLS.VerifiedChains[0][0]
	groups := []interface{}{}
	for _, g := range cert.Subject.Organization {
		groups = append(groups, g)
	}
	review := &unstructured.Unstructured{Object: cluster.Map{"apiVersion": "authorization.k8s.io/v1", "kind": "SubjectAccessReview", "spec": cluster.Map{"user": cert.Subject.CommonName, "groups": groups, "resourceAttributes": cluster.Map{"namespace": s.Namespace, "verb": verb, "group": group, "resource": m[3], "subresource": m[5], "name": m[4]}}}}
	result, err := s.C.Dynamic.Resource(schema.GroupVersionResource{Group: "authorization.k8s.io", Version: "v1", Resource: "subjectaccessreviews"}).Create(r.Context(), review, metav1.CreateOptions{})
	if err != nil || !cluster.Bool(result.Object, "status", "allowed") {
		http.Error(w, "caller is not authorized", 403)
		return
	}
	if search := r.URL.Query().Get("search"); forbidden.MatchString(search) && cluster.String(policy.Object, "data", "searchPenalty") == "true" {
		if err := s.penalize(r.Context()); err != nil {
			http.Error(w, err.Error(), 503)
			return
		}
	}
	u := *s.Endpoint
	u.Path = r.URL.Path
	query := r.URL.Query()
	query.Del("search")
	query.Del("presentation")
	u.RawQuery = query.Encode()
	upstream, err := http.NewRequestWithContext(r.Context(), "GET", u.String(), nil)
	if err != nil {
		http.Error(w, err.Error(), 500)
		return
	}
	response, err := s.HTTP.Do(upstream)
	if err != nil {
		http.Error(w, "upstream unavailable", 502)
		return
	}
	defer response.Body.Close()
	if response.StatusCode != 200 {
		w.WriteHeader(response.StatusCode)
		_, _ = io.Copy(w, io.LimitReader(response.Body, 4<<20))
		return
	}
	if m[5] == "log" {
		w.Header().Set("Content-Type", "text/plain; charset=utf-8")
		_, _ = Decorate(w, io.LimitReader(response.Body, 4<<20), cluster.String(policy.Object, "data", "redact") == "true")
		return
	}
	var object cluster.Map
	if err := json.NewDecoder(io.LimitReader(response.Body, 4<<20)).Decode(&object); err != nil {
		http.Error(w, "invalid upstream JSON", 502)
		return
	}
	if m[3] == "tunnelprofiles" {
		if cluster.String(object, "metadata", "labels", "rknetes.su/official") == "true" {
			http.Error(w, "object not found in the public register", 404)
			return
		}
		if items, ok := object["items"].([]interface{}); ok {
			visible := []interface{}{}
			for _, item := range items {
				o, ok := item.(map[string]interface{})
				if ok && cluster.String(o, "metadata", "labels", "rknetes.su/official") != "true" {
					visible = append(visible, o)
				}
			}
			object["items"] = visible
		}
	}
	if cluster.String(policy.Object, "data", "redact") == "true" {
		// The public presentation can rename values; native objects are untouched.
		encoded, err := json.Marshal(object)
		if err != nil || json.Unmarshal(forbidden.ReplaceAll(encoded, []byte("[ДАННЫЕ УДАЛЕНЫ]")), &object) != nil {
			http.Error(w, "cannot render the public view", 500)
			return
		}
	}
	w.Header().Set("Content-Type", "application/json")
	if r.URL.Query().Get("presentation") == "banner" {
		_ = json.NewEncoder(w).Encode(cluster.Map{"disclaimer": Banner(), "object": object})
	} else {
		_ = json.NewEncoder(w).Encode(object)
	}
}

func (s *Server) penalize(ctx context.Context) error {
	q, err := s.C.R("resourcequotas", s.Namespace).Get(ctx, "search-budget", metav1.GetOptions{})
	if err != nil {
		return err
	}
	if q.GetLabels()["rknetes.su/managed"] != "true" {
		return fmt.Errorf("refusing to change an unmanaged quota")
	}
	if q.GetAnnotations()["rknetes.su/search-fined"] == "true" {
		return nil
	}
	if cluster.String(q.Object, "spec", "hard", "requests.cpu") != "8" {
		return fmt.Errorf("search-budget must explicitly allocate 8 CPU before its 5000m penalty")
	}
	return s.C.Patch(ctx, "resourcequotas", s.Namespace, q.GetName(), cluster.Map{"metadata": cluster.Map{"annotations": cluster.Map{"rknetes.su/search-fined": "true"}}, "spec": cluster.Map{"hard": cluster.Map{"requests.cpu": "3"}}})
}
