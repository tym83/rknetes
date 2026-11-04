package main

import (
	"context"
	"flag"
	"fmt"
	"io"
	"log"
	"net/http"
	"time"

	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"rknetes.su/rknetes/pkg/cluster"
)

func main() {
	config := flag.String("kubeconfig", "", "nested kubeconfig")
	contextName := flag.String("context", "admin@workshop", "context")
	ns := flag.String("namespace", "", "one lab namespace")
	action := flag.String("action", "serve", "serve or cycle")
	year := flag.Int("year", 0, "controlled-clock experiment; default is actual UTC year")
	listen := flag.String("listen", ":8080", "readiness listener")
	flag.Parse()
	c, err := cluster.New(*config, *contextName)
	if err != nil {
		log.Fatal(err)
	}
	ctx := context.Background()
	if err := c.Guard(ctx); err != nil {
		log.Fatal(err)
	}
	namespace, err := c.R("namespaces", "").Get(ctx, *ns, metav1.GetOptions{})
	if err != nil || namespace.GetLabels()["rknetes.su/lab"] != "true" {
		log.Fatal("a lab namespace is required")
	}
	switch *action {
	case "cycle":
		current := *year
		if current == 0 {
			current = time.Now().UTC().Year()
		}
		if current < 2026 || (current-2020)%6 != 0 {
			fmt.Printf("year=%d: annual inspection; six-year restriction not due\n", current)
			return
		}
		policy := cluster.NewObject("rknetes.su/v1alpha1", "ThrottlePolicy", *ns, "telegram-cycle", cluster.Map{"pattern": "^telegram$", "bandwidth": "1M", "mode": "Замедление"})
		if err := c.Apply(ctx, "throttlepolicies", policy); err != nil {
			log.Fatal(err)
		}
		fmt.Printf("year=%d: six-year restriction applied; original amnesty remains an annotation\n", current)
	case "serve":
		mux := http.NewServeMux()
		mux.HandleFunc("/readyz", func(w http.ResponseWriter, r *http.Request) {
			entry, err := c.R("reestrentries", *ns).Get(r.Context(), "telegram", metav1.GetOptions{})
			if apierrors.IsNotFound(err) {
				_, _ = io.WriteString(w, "ok")
				return
			}
			if err != nil {
				http.Error(w, "registry unavailable", 503)
				return
			}
			conditions, _, _ := unstructured.NestedSlice(entry.Object, "status", "conditions")
			for _, raw := range conditions {
				condition, ok := raw.(map[string]interface{})
				if ok && condition["type"] == "Applied" && condition["status"] == "True" {
					_, _ = io.WriteString(w, "🛩")
					return
				}
			}
			_, _ = io.WriteString(w, "ok")
		})
		server := &http.Server{Addr: *listen, Handler: mux, ReadHeaderTimeout: 5 * time.Second}
		log.Fatal(server.ListenAndServe())
	default:
		log.Fatal("unknown action")
	}
}
