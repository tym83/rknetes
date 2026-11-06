package maxlet

import (
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"net/http"
	"net/http/httptest"
	"testing"

	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/client-go/dynamic/fake"
	"k8s.io/client-go/rest"
	ktesting "k8s.io/client-go/testing"
	"rknetes.su/rknetes/pkg/cluster"
)

func TestDiscoveryCannotBypassResourceAuthorization(t *testing.T) {
	calls := 0
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		calls++
		if r.Header.Get("Impersonate-Extra-Scope") != "" {
			t.Error("forwarded impersonation")
		}
		w.Write([]byte("ok"))
	}))
	defer upstream.Close()
	ns := cluster.NewObject("v1", "Namespace", "", "lab-logs", nil)
	ns.SetLabels(map[string]string{"rknetes.su/lab": "true"})
	dynamic := fake.NewSimpleDynamicClient(runtime.NewScheme(), ns)
	dynamic.PrependReactor("create", "subjectaccessreviews", func(a ktesting.Action) (bool, runtime.Object, error) {
		object := a.(ktesting.CreateAction).GetObject().(*cluster.Object)
		if cluster.String(object.Object, "spec", "resourceAttributes", "verb") != "get" || cluster.String(object.Object, "spec", "resourceAttributes", "subresource") != "log" {
			t.Error("wrong log authorization")
		}
		result := cluster.NewObject("authorization.k8s.io/v1", "SubjectAccessReview", "", "", nil)
		result.Object["status"] = cluster.Map{"allowed": false}
		return true, result, nil
	})
	server, err := New(&cluster.Client{Dynamic: dynamic, Config: &rest.Config{Host: upstream.URL}}, t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	for _, item := range []struct {
		path string
		want int
	}{{"/apis/rknetes.su/v1alpha1/namespaces/lab-logs/tunnelprofiles", 404}, {"/api/v1/namespaces/lab-logs/pods/p/log", 403}, {"/apis/rknetes.su/v1alpha1", 200}} {
		r := httptest.NewRequest("GET", item.path, nil)
		r.TLS = &tls.ConnectionState{VerifiedChains: [][]*x509.Certificate{{{Subject: pkix.Name{CommonName: "reader"}}}}}
		r.Header.Set("Impersonate-Extra-Scope", "admin")
		w := httptest.NewRecorder()
		server.ServeHTTP(w, r)
		if w.Code != item.want {
			t.Errorf("%s: %d", item.path, w.Code)
		}
	}
	if calls != 1 {
		t.Fatalf("upstream calls=%d", calls)
	}
}
