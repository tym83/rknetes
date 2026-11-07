package admission

import (
	"context"
	"fmt"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"rknetes.su/rknetes/pkg/cluster"
)

func (s *Server) archive(ctx context.Context, req *Request) ([]cluster.Map, error) {
	policies, err := s.C.List(ctx, "archivepolicies", req.Namespace)
	if err != nil {
		return nil, err
	}
	var selected *cluster.Object
	for i := range policies {
		p := &policies[i]
		selector := cluster.Labels(p.Object, "spec", "selector")
		if len(selector) > 0 && cluster.Match(cluster.Labels(req.Object, "metadata", "labels"), selector) {
			if selected != nil {
				return nil, fmt.Errorf("one ArchivePolicy may select a Pod")
			}
			selected = p
		}
	}
	if selected == nil {
		return nil, nil
	}
	if cluster.Bool(req.Object, "spec", "hostNetwork") {
		return nil, fmt.Errorf("archive requires a private Pod network")
	}
	if cluster.Int(selected.Object, 180, "spec", "retentionDays") < 180 {
		return nil, fmt.Errorf("archive retention must be at least180days")
	}
	runtime, err := s.C.R("configmaps", "rknet-system").Get(ctx, "runtime-artifacts", metav1.GetOptions{})
	if err != nil {
		return nil, err
	}
	url := cluster.String(runtime.Object, "data", "url") + "/archive-agent"
	hash := cluster.String(runtime.Object, "data", "sha256.archive-agent")
	image := cluster.String(runtime.Object, "data", "image")
	if len(hash) != 64 || image == "" {
		return nil, fmt.Errorf("immutable archive artifact required")
	}
	spec := req.Object["spec"].(map[string]interface{})
	containers, _, _ := unstructured.NestedSlice(req.Object, "spec", "containers")
	for _, raw := range containers {
		if raw.(map[string]interface{})["name"] == "yarovaya" {
			return nil, nil
		}
	}
	volumes, _, _ := unstructured.NestedSlice(req.Object, "spec", "volumes")
	volume := cluster.String(selected.Object, "spec", "volumeName")
	claim := cluster.String(selected.Object, "spec", "claimName")
	if claim != "" {
		volume = "yarovaya-storage"
		volumes = append(volumes, cluster.Map{"name": volume, "persistentVolumeClaim": cluster.Map{"claimName": claim}})
	} else {
		found := false
		for _, raw := range volumes {
			v := raw.(map[string]interface{})
			if v["name"] == volume {
				found = true
			}
		}
		if !found {
			return nil, fmt.Errorf("archive requires a PVC or an explicitly shared Pod volume")
		}
	}
	volumes = append(volumes, cluster.Map{"name": "yarovaya-binary", "emptyDir": cluster.Map{}})
	init, _, _ := unstructured.NestedSlice(req.Object, "spec", "initContainers")
	init = append(init, cluster.Map{"name": "yarovaya-binary", "image": image, "command": []interface{}{"sh", "-ec", `curl -fsS "$1" -o /rk/archive-agent; echo "$2  /rk/archive-agent" | sha256sum -c -; chmod +x /rk/archive-agent`, "download", url, hash}, "volumeMounts": []interface{}{cluster.Map{"name": "yarovaya-binary", "mountPath": "/rk"}}})
	env := []interface{}{}
	for name, path := range map[string]string{"POD_NAMESPACE": "metadata.namespace", "POD_NAME": "metadata.name", "POD_UID": "metadata.uid"} {
		env = append(env, cluster.Map{"name": name, "valueFrom": cluster.Map{"fieldRef": cluster.Map{"fieldPath": path}}})
	}
	containers = append(containers, cluster.Map{"name": "yarovaya", "image": image, "command": []interface{}{"/rk/archive-agent", "--policy", selected.GetName()}, "env": env, "securityContext": cluster.Map{"capabilities": cluster.Map{"add": []interface{}{"NET_RAW"}}}, "resources": cluster.Map{"requests": cluster.Map{"cpu": "20m", "memory": "64Mi"}, "limits": cluster.Map{"cpu": "1", "memory": "256Mi"}}, "volumeMounts": []interface{}{cluster.Map{"name": "yarovaya-binary", "mountPath": "/rk", "readOnly": true}, cluster.Map{"name": volume, "mountPath": "/archive"}}})
	patches := []cluster.Map{}
	for key, value := range map[string]interface{}{"volumes": volumes, "initContainers": init, "containers": containers} {
		op := "add"
		if _, ok := spec[key]; ok {
			op = "replace"
		}
		patches = append(patches, cluster.Map{"op": op, "path": "/spec/" + key, "value": value})
	}
	return patches, nil
}
