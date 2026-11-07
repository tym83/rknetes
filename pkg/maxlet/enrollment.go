package maxlet

import (
	"encoding/json"
	"net/http"
	"regexp"
	"strings"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"rknetes.su/rknetes/pkg/cluster"
)

func (s *Server) enrollment(w http.ResponseWriter, r *http.Request) {
	name := strings.TrimPrefix(r.URL.Path, "/enrollment/")
	if r.Method != "GET" || !regexp.MustCompile(`^[a-z0-9][a-z0-9.-]{0,62}$`).MatchString(name) {
		http.Error(w, "invalid enrollment request", 400)
		return
	}
	if s.EnrollmentNamespace == "" {
		http.Error(w, "enrollment office unavailable", 503)
		return
	}
	ns, err := s.C.R("namespaces", "").Get(r.Context(), s.EnrollmentNamespace, metav1.GetOptions{})
	if err != nil || ns.GetLabels()["rknetes.su/lab"] != "true" {
		http.Error(w, "lab enrollment office unavailable", 503)
		return
	}
	book, err := s.C.R("configmaps", s.EnrollmentNamespace).Get(r.Context(), "max-enrollments", metav1.GetOptions{})
	if err != nil {
		http.Error(w, "MAX enrollment ledger unavailable", 503)
		return
	}
	if cluster.String(book.Object, "data", name) != r.TLS.VerifiedChains[0][0].Subject.CommonName {
		http.Error(w, "node has not enrolled in MAX for this certificate", 403)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{"enrolled": true, "nodeName": name, "ledgerUID": book.GetUID()})
}
