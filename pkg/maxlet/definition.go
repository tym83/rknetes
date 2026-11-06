package maxlet

import (
	"bytes"
	"encoding/json"
	"io"
	"net/http"
	"strings"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"rknetes.su/rknetes/pkg/cluster"
)

// The optional large-definition experiment admits only its lab API group.
// Normal MAX installations carry pod calls/logs and discovery only.
func (s *Server) definition(w http.ResponseWriter, r *http.Request) {
	const base = "/apis/apiextensions.k8s.io/v1/customresourcedefinitions"
	name := strings.TrimPrefix(strings.TrimPrefix(r.URL.Path, base), "/")
	verb := ""
	switch r.Method {
	case "GET":
		verb = "get"
	case "POST":
		verb = "create"
	case "PUT":
		verb = "update"
	case "PATCH":
		verb = "patch"
	case "DELETE":
		verb = "delete"
	}
	if verb == "" {
		http.Error(w, "unsupported definition operation", 405)
		return
	}
	if r.Method == "POST" || r.Method == "PUT" {
		body, err := io.ReadAll(io.LimitReader(r.Body, 2<<20))
		if err != nil {
			http.Error(w, "incomplete definition body", 400)
			return
		}
		var object cluster.Object
		if json.Unmarshal(body, &object.Object) != nil || object.GetLabels()["rknetes.su/lab"] != "true" || cluster.String(object.Object, "spec", "group") != "lab.rknetes.su" {
			http.Error(w, "labelled lab.rknetes.su definition required", 403)
			return
		}
		if name != "" && name != object.GetName() {
			http.Error(w, "definition name mismatch", 400)
			return
		}
		name = object.GetName()
		r.Body = io.NopCloser(bytes.NewReader(body))
	}
	if !strings.HasSuffix(name, ".lab.rknetes.su") || strings.Contains(name, "/") {
		http.Error(w, "lab definition required", 403)
		return
	}
	cert := r.TLS.VerifiedChains[0][0]
	review := &unstructured.Unstructured{Object: cluster.Map{"apiVersion": "authorization.k8s.io/v1", "kind": "SubjectAccessReview", "spec": cluster.Map{"user": cert.Subject.CommonName, "groups": toAny(cert.Subject.Organization), "resourceAttributes": cluster.Map{"verb": verb, "group": "apiextensions.k8s.io", "resource": "customresourcedefinitions", "name": name}}}}
	result, err := s.C.Dynamic.Resource(schema.GroupVersionResource{Group: "authorization.k8s.io", Version: "v1", Resource: "subjectaccessreviews"}).Create(r.Context(), review, metav1.CreateOptions{})
	if err != nil || !cluster.Bool(result.Object, "status", "allowed") {
		http.Error(w, "definition operation forbidden", 403)
		return
	}
	if r.Method == "PATCH" {
		http.Error(w, "use a complete labelled replacement for this lab experiment", 405)
		return
	}
	s.Proxy.ServeHTTP(w, r)
}
