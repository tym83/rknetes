package watchoffice

import (
	"context"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"net/http"
	"net/http/httptest"
	"testing"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"k8s.io/client-go/dynamic/fake"
	"k8s.io/client-go/rest"
	ktesting "k8s.io/client-go/testing"
	"rknetes.su/rknetes/pkg/cluster"
)

func TestRegistrationSurvivesDisconnectAndGatewayRestart(t *testing.T) {
	upstreamCalls := 0
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		upstreamCalls++
		w.Write([]byte("{\"type\":\"ADDED\"}\n"))
	}))
	defer upstream.Close()
	ns := cluster.NewObject("v1", "Namespace", "", "lab-blogger", nil)
	ns.SetLabels(map[string]string{"rknetes.su/lab": "true"})
	registration := cluster.NewObject("rknetes.su/v1alpha1", "BloggerRegistration", "lab-blogger", "channel", cluster.Map{
		"resource": "configmaps", "name": "channel", "threshold": int64(3), "registered": false,
	})
	registration.Object["status"] = cluster.Map{"observedConcurrentWatches": int64(4)}
	client := fake.NewSimpleDynamicClientWithCustomListKinds(runtime.NewScheme(), map[schema.GroupVersionResource]string{
		cluster.Resource("bloggerregistrations"): "BloggerRegistrationList",
		cluster.Resource("configmaps"):           "ConfigMapList",
	}, ns, registration)
	client.PrependReactor("create", "subjectaccessreviews", func(ktesting.Action) (bool, runtime.Object, error) {
		response := cluster.NewObject("authorization.k8s.io/v1", "SubjectAccessReview", "", "allowed", nil)
		response.Object["status"] = cluster.Map{"allowed": true}
		return true, response, nil
	})
	c := &cluster.Client{Dynamic: client, Config: &rest.Config{Host: upstream.URL}}
	request := func(server *Server) int {
		r := httptest.NewRequest("GET", "/api/v1/namespaces/lab-blogger/configmaps?watch=true&fieldSelector=metadata.name%3Dchannel", nil)
		r.TLS = &tls.ConnectionState{VerifiedChains: [][]*x509.Certificate{{{Subject: pkix.Name{CommonName: "reader"}}}}}
		w := httptest.NewRecorder()
		server.ServeHTTP(w, r)
		return w.Code
	}
	// A new gateway has no active connections. The persisted audience still
	// requires registration, even after disconnect and process replacement.
	for i := 0; i < 2; i++ {
		server, err := New(c)
		if err != nil {
			t.Fatal(err)
		}
		if code := request(server); code != http.StatusUnavailableForLegalReasons {
			t.Fatalf("unregistered reconnect after restart returned %d, want 451", code)
		}
	}
	if upstreamCalls != 0 {
		t.Fatalf("unregistered reader reached upstream %d times", upstreamCalls)
	}
	if err := c.Patch(context.Background(), "bloggerregistrations", "lab-blogger", "channel", cluster.Map{"spec": cluster.Map{"registered": true}}); err != nil {
		t.Fatal(err)
	}
	server, err := New(c)
	if err != nil {
		t.Fatal(err)
	}
	if code := request(server); code != http.StatusOK {
		t.Fatalf("registered watch returned %d", code)
	}
	current, err := c.R("bloggerregistrations", "lab-blogger").Get(context.Background(), "channel", metav1.GetOptions{})
	if err != nil {
		t.Fatal(err)
	}
	if peak := cluster.Int(current.Object, 0, "status", "observedConcurrentWatches"); peak != 4 {
		t.Fatalf("persisted peak changed to %d", peak)
	}
	if upstreamCalls != 1 {
		t.Fatalf("registered upstream requests: %d, want 1", upstreamCalls)
	}
}
