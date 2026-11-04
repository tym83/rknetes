package presentation

import (
	"bytes"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/client-go/dynamic/fake"
	"k8s.io/client-go/rest"
	ktesting "k8s.io/client-go/testing"
	"rknetes.su/rknetes/pkg/cluster"
)

func TestDisclaimerUsesTwentyFourWordsAndDuplicatesRunes(t *testing.T) {
	if len(strings.Fields(Disclaimer)) != 24 {
		t.Fatal("disclaimer must contain exactly 24 words")
	}
	runes := []rune(Banner())
	for i, r := range []rune(Disclaimer) {
		if runes[2*i] != r || runes[2*i+1] != r {
			t.Fatal("Unicode character was not duplicated")
		}
	}
	var output bytes.Buffer
	n, err := Decorate(&output, strings.NewReader("GET / 200\nwireguard connected\n"), true)
	if err != nil || n != int64(output.Len()) || strings.Count(output.String(), Banner()) != 2 || strings.Contains(output.String(), "wireguard") {
		t.Fatalf("invalid measured presentation: bytes=%d error=%v", n, err)
	}
}

func TestPublicViewAuthorizationFilteringAndDestructiveProfile(t *testing.T) {
	calls := 0
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		calls++
		if r.Header.Get("Authorization") != "" || r.Header.Get("Impersonate-User") != "" {
			t.Error("untrusted request credentials reached upstream")
		}
		io.WriteString(w, `{"kind":"TunnelProfileList","items":[{"metadata":{"name":"official","labels":{"rknetes.su/official":"true"}}},{"metadata":{"name":"wireguard"}}]}`)
	}))
	defer upstream.Close()
	namespace := &unstructured.Unstructured{Object: cluster.Map{"apiVersion": "v1", "kind": "Namespace", "metadata": cluster.Map{"name": "lab-view", "labels": cluster.Map{"rknetes.su/lab": "true"}}}}
	policy := &unstructured.Unstructured{Object: cluster.Map{"apiVersion": "v1", "kind": "ConfigMap", "metadata": cluster.Map{"name": "presentation-policy", "namespace": "lab-view"}, "data": cluster.Map{"mode": "normal", "redact": "true"}}}
	d := fake.NewSimpleDynamicClient(runtime.NewScheme(), namespace, policy)
	allowed := true
	d.PrependReactor("create", "subjectaccessreviews", func(action ktesting.Action) (bool, runtime.Object, error) {
		o := action.(ktesting.CreateAction).GetObject().(*unstructured.Unstructured)
		if cluster.String(o.Object, "spec", "resourceAttributes", "namespace") != "lab-view" || cluster.String(o.Object, "spec", "resourceAttributes", "verb") != "list" {
			t.Error("incorrect authorization attributes")
		}
		return true, &unstructured.Unstructured{Object: cluster.Map{"status": cluster.Map{"allowed": allowed}}}, nil
	})
	c := &cluster.Client{Dynamic: d, Config: &rest.Config{Host: upstream.URL}}
	s, err := New(c, "lab-view")
	if err != nil {
		t.Fatal(err)
	}
	request := func(path string, certificate bool) *httptest.ResponseRecorder {
		r := httptest.NewRequest("GET", path, nil)
		r.Header.Set("Authorization", "Bearer untrusted")
		r.Header.Set("Impersonate-User", "untrusted")
		if certificate {
			r.TLS = &tls.ConnectionState{VerifiedChains: [][]*x509.Certificate{{{Subject: pkix.Name{CommonName: "reader"}}}}}
		}
		w := httptest.NewRecorder()
		s.ServeHTTP(w, r)
		return w
	}
	path := "/apis/rknetes.su/v1alpha1/namespaces/lab-view/tunnelprofiles?presentation=banner"
	if w := request(path, false); w.Code != 401 || calls != 0 {
		t.Fatal("unauthenticated request reached upstream")
	}
	allowed = false
	if w := request(path, true); w.Code != 403 || calls != 0 {
		t.Fatal("unauthorized request reached upstream")
	}
	allowed = true
	w := request(path, true)
	var object cluster.Map
	if w.Code != 200 || json.Unmarshal(w.Body.Bytes(), &object) != nil || strings.Contains(w.Body.String(), "official") || strings.Contains(w.Body.String(), "wireguard") || !strings.Contains(w.Body.String(), "ДАННЫЕ УДАЛЕНЫ") {
		t.Fatalf("public view did not filter and redact: %s", w.Body.String())
	}
	if w := request(strings.Replace(path, "lab-view", "another-tenant", 1), true); w.Code != 400 || calls != 1 {
		t.Fatal("namespace boundary was crossed")
	}
	policy.Object["data"] = cluster.Map{"mode": "destructive"}
	if _, err := c.R("configmaps", "lab-view").Update(t.Context(), policy, metav1.UpdateOptions{}); err != nil {
		t.Fatal(err)
	}
	if w := request("/version", true); w.Code != 451 || calls != 1 || !strings.Contains(w.Body.String(), "UnavailableForLegalReasons") {
		t.Fatal("destructive gateway profile must reject even discovery without contacting upstream")
	}
}
