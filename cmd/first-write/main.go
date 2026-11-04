// first-write is a concrete PostgreSQL adapter, not a transparent SQL proxy.
package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"
	"time"

	"github.com/jackc/pgx/v5"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"rknetes.su/rknetes/pkg/cluster"
)

type write struct {
	ID    int64  `json:"id"`
	Value string `json:"value"`
}

func main() {
	ns := flag.String("namespace", "", "one lab namespace")
	workload := flag.String("workload", "orders", "selected StatefulSet")
	replica := flag.String("replica-service", "replica", "replica Service in this namespace")
	listen := flag.String("listen", ":8080", "HTTP adapter address")
	flag.Parse()
	c, err := cluster.New("", "admin@workshop")
	if err != nil {
		log.Fatal(err)
	}
	if err := c.Guard(context.Background()); err != nil {
		log.Fatal(err)
	}
	if os.Getenv("PGPASSWORD") == "" {
		log.Fatal("database password is required")
	}
	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) { _, _ = w.Write([]byte("ok")) })
	mux.HandleFunc("/write", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "POST" {
			http.Error(w, "POST required", 405)
			return
		}
		ctx, cancel := context.WithTimeout(r.Context(), 8*time.Second)
		defer cancel()
		namespace, err := c.R("namespaces", "").Get(ctx, *ns, metav1.GetOptions{})
		if err != nil || namespace.GetLabels()["rknetes.su/lab"] != "true" {
			http.Error(w, "lab namespace required", 403)
			return
		}
		var request write
		if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 8192)).Decode(&request); err != nil || request.ID <= 0 || len(request.Value) > 4096 {
			http.Error(w, "positive id and bounded value required", 400)
			return
		}
		selected, err := c.R("statefulsets", *ns).Get(ctx, *workload, metav1.GetOptions{})
		if err != nil {
			http.Error(w, "selected StatefulSet unavailable", 503)
			return
		}
		policies, err := c.List(ctx, "databoundarypolicies", *ns)
		if err != nil {
			http.Error(w, "boundary policy unavailable", 503)
			return
		}
		var policy *cluster.Object
		for i := range policies {
			selector := cluster.Labels(policies[i].Object, "spec", "selector")
			if len(selector) > 0 && cluster.Match(selected.GetLabels(), selector) {
				if policy != nil {
					http.Error(w, "ambiguous first-write policies", 409)
					return
				}
				policy = &policies[i]
			}
		}
		if policy == nil {
			http.Error(w, "DataBoundaryPolicy required", 503)
			return
		}
		primary := cluster.String(policy.Object, "spec", "primaryService")
		for _, name := range []string{primary, *replica} {
			service, err := c.R("services", *ns).Get(ctx, name, metav1.GetOptions{})
			if err != nil || service.GetLabels()["rknetes.su/labdb"] != "true" || cluster.String(service.Object, "spec", "type") != "ClusterIP" || len(cluster.Strings(service.Object, "spec", "externalIPs")) != 0 {
				http.Error(w, "two labelled internal database Services are required", 403)
				return
			}
		}
		result := cluster.Map{"id": request.ID, "primaryCommitted": false, "replicaCommitted": false}
		code := http.StatusServiceUnavailable
		if err := persist(ctx, primary+"."+*ns+".svc", request); err != nil {
			result["failure"] = "domestic primary unavailable; no replica write attempted"
		} else {
			result["primaryCommitted"] = true
			result["primaryCommitObservedAt"] = time.Now().UTC().Format(time.RFC3339Nano)
			result["replicaWriteStartedAt"] = time.Now().UTC().Format(time.RFC3339Nano)
			if err := persist(ctx, *replica+"."+*ns+".svc", request); err != nil {
				result["failure"] = "primary committed; replica unavailable; retry the same id"
			} else {
				result["replicaCommitted"] = true
				code = http.StatusCreated
			}
		}
		// Report observed acknowledgements; a primary commit is never rolled back
		// merely because the later replication failed.
		_ = c.Status(r.Context(), "databoundarypolicies", policy, cluster.Map{"lastWrite": result})
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(code)
		_ = json.NewEncoder(w).Encode(result)
	})
	server := &http.Server{Addr: *listen, Handler: mux, ReadHeaderTimeout: 5 * time.Second}
	log.Fatal(server.ListenAndServe())
}

func persist(parent context.Context, host string, request write) error {
	ctx, cancel := context.WithTimeout(parent, 3*time.Second)
	defer cancel()
	config, err := pgx.ParseConfig("postgres://postgres@" + host + ":5432/postgres?sslmode=disable")
	if err != nil {
		return err
	}
	config.Password = os.Getenv("PGPASSWORD")
	conn, err := pgx.ConnectConfig(ctx, config)
	if err != nil {
		return err
	}
	defer conn.Close(ctx)
	tx, err := conn.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)
	for _, query := range []string{"SET LOCAL synchronous_commit=on", "CREATE TABLE IF NOT EXISTS writes (id bigint PRIMARY KEY, value text NOT NULL)"} {
		if _, err := tx.Exec(ctx, query); err != nil {
			return err
		}
	}
	if _, err := tx.Exec(ctx, "INSERT INTO writes(id,value) VALUES($1,$2) ON CONFLICT(id) DO UPDATE SET value=EXCLUDED.value", request.ID, request.Value); err != nil {
		return fmt.Errorf("durable write: %w", err)
	}
	return tx.Commit(ctx)
}
