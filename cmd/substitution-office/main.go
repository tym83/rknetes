// The deliberately non-idempotent laboratory mutator measures Kubernetes' bound.
package main

import (
	"encoding/base64"
	"encoding/json"
	"flag"
	"log"
	"net/http"
	"strconv"
	"time"

	"rknetes.su/rknetes/pkg/admission"
	"rknetes.su/rknetes/pkg/cluster"
)

func main() {
	listen := flag.String("listen", ":9443", "listen address")
	cert := flag.String("tls-cert", "/tls/tls.crt", "server certificate")
	key := flag.String("tls-key", "/tls/tls.key", "server key")
	flag.Parse()
	mux := http.NewServeMux()
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		var review admission.Review
		if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 4<<20)).Decode(&review); err != nil || review.Request == nil {
			http.Error(w, "invalid AdmissionReview", 400)
			return
		}
		req := review.Request
		annotations := cluster.Labels(req.Object, "metadata", "annotations")
		if annotations == nil {
			annotations = map[string]string{}
		}
		patches := []cluster.Map{}
		switch r.URL.Path {
		case "/substitute":
			passes, _ := strconv.Atoi(annotations["rknetes.su/substitution-passes"])
			annotations["rknetes.su/substitution-passes"] = strconv.Itoa(passes + 1)
			// Replace the image by itself: a reportable substitution with no new code.
			spec, _ := req.Object["spec"].(map[string]interface{})
			containers, _ := spec["containers"].([]interface{})
			if len(containers) > 0 {
				patches = append(patches, cluster.Map{"op": "replace", "path": "/spec/containers/0/image", "value": cluster.String(containers[0].(map[string]interface{}), "image")})
			}
			log.Printf("uid=%s substituted-components=%d", req.UID, passes+1)
		case "/next-agency":
			annotations["rknetes.su/next-agency"] = "reviewed"
		default:
			http.NotFound(w, r)
			return
		}
		patches = append(patches, cluster.Map{"op": "add", "path": "/metadata/annotations", "value": annotations})
		patch, err := json.Marshal(patches)
		if err != nil {
			http.Error(w, err.Error(), 500)
			return
		}
		patchType := "JSONPatch"
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(admission.Review{APIVersion: "admission.k8s.io/v1", Kind: "AdmissionReview", Response: &admission.Response{UID: req.UID, Allowed: true, Patch: base64.StdEncoding.EncodeToString(patch), PatchType: &patchType}})
	})
	server := &http.Server{Addr: *listen, Handler: mux, ReadHeaderTimeout: 10 * time.Second}
	log.Fatal(server.ListenAndServeTLS(*cert, *key))
}
