package controller

import (
	"context"
	"fmt"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"rknetes.su/rknetes/pkg/cluster"
	"slices"
)

func (r *Controller) Pigeons(ctx context.Context, ns string) error {
	policies, err := r.C.List(ctx, "pigeons", ns)
	if err != nil {
		return err
	}
	for i := range policies {
		p := &policies[i]
		uid := string(p.GetUID())
		base := "pigeon-" + uid
		destination := cluster.String(p.Object, "spec", "destinationNamespace")
		claimName := cluster.String(p.Object, "spec", "claimName")
		if claimName == "" {
			claimName = p.GetName()
		}
		if p.GetDeletionTimestamp() != nil {
			if previous := cluster.String(p.Object, "status", "destinationNamespace"); previous != "" {
				destination = previous
			}
			if previous := cluster.String(p.Object, "status", "claimName"); previous != "" {
				claimName = previous
			}
		} else if previous := cluster.String(p.Object, "status", "claimName"); previous != "" && previous != claimName {
			return fmt.Errorf("recreate Pigeon to change its claim name")
		}
		if destination == ns || destination == "" {
			return fmt.Errorf("a separate destination lab namespace is required")
		}
		target, err := r.C.R("namespaces", "").Get(ctx, destination, metav1.GetOptions{})
		if err != nil && !(apierrors.IsNotFound(err) && p.GetDeletionTimestamp() != nil) {
			return err
		}
		if err == nil && target.GetLabels()["rknetes.su/lab"] != "true" {
			return fmt.Errorf("destination must be a labelled lab namespace")
		}
		if err == nil {
			if previous := cluster.String(p.Object, "status", "destinationUID"); previous != "" && previous != string(target.GetUID()) {
				return fmt.Errorf("destination namespace was recreated; refusing unrelated namespace")
			}
		}
		if old := cluster.String(p.Object, "status", "destinationNamespace"); old != "" && old != destination {
			return fmt.Errorf("recreate Pigeon to change destination namespace")
		}
		node := cluster.String(p.Object, "spec", "nodeName")
		if p.GetDeletionTimestamp() != nil {
			if previous := cluster.String(p.Object, "status", "nodeName"); previous != "" {
				node = previous
			}
		}
		if node == "" {
			return fmt.Errorf("an explicit nested nodeName is required for the local shared spool")
		}
		if old := cluster.String(p.Object, "status", "nodeName"); old != "" && old != node {
			return fmt.Errorf("recreate Pigeon to change its spool node")
		}
		if _, err := r.C.R("nodes", "").Get(ctx, node, metav1.GetOptions{}); err != nil && p.GetDeletionTimestamp() == nil {
			return err
		}
		sides := []struct{ ns, peer, address, peerIP, suffix string }{{ns, destination, "198.18.0.1/30", "198.18.0.2", "source"}, {destination, ns, "198.18.0.2/30", "198.18.0.1", "destination"}}
		finalizer := "rknetes.su/pigeon-cleanup"
		if p.GetDeletionTimestamp() != nil {
			pending := false
			for _, side := range sides {
				for _, item := range []struct{ resource, ns, name string }{{"pods", side.ns, p.GetName()}, {"persistentvolumeclaims", side.ns, claimName}, {"persistentvolumes", "", base + "-" + side.suffix}} {
					old, err := r.C.R(item.resource, item.ns).Get(ctx, item.name, metav1.GetOptions{})
					if apierrors.IsNotFound(err) {
						continue
					}
					if err != nil {
						return err
					}
					if old.GetLabels()["rknetes.su/owner"] != uid {
						return fmt.Errorf("refusing unrelated carrier cleanup")
					}
					pending = true
					objectUID := old.GetUID()
					if err := r.C.R(item.resource, item.ns).Delete(ctx, item.name, metav1.DeleteOptions{Preconditions: &metav1.Preconditions{UID: &objectUID}}); err != nil && !apierrors.IsNotFound(err) {
						return err
					}
				}
			}
			if pending {
				continue
			}
			finals := []string{}
			for _, f := range p.GetFinalizers() {
				if f != finalizer {
					finals = append(finals, f)
				}
			}
			if err := r.C.Patch(ctx, "pigeons", ns, p.GetName(), cluster.Map{"metadata": cluster.Map{"finalizers": finals}}); err != nil {
				return err
			}
			continue
		}
		if !slices.Contains(p.GetFinalizers(), finalizer) {
			if err := r.C.Patch(ctx, "pigeons", ns, p.GetName(), cluster.Map{"metadata": cluster.Map{"finalizers": append(p.GetFinalizers(), finalizer)}}); err != nil {
				return err
			}
		}
		if cluster.String(p.Object, "status", "destinationUID") == "" {
			if err := r.C.Status(ctx, "pigeons", p, cluster.Map{"destinationNamespace": destination, "destinationUID": string(target.GetUID()), "nodeName": node, "claimName": claimName}); err != nil {
				return err
			}
		}
		url, hash, image, err := r.artifact(ctx, "pigeon")
		if err != nil {
			return err
		}
		ready := int64(0)
		for _, side := range sides {
			pv := owned(cluster.NewObject("v1", "PersistentVolume", "", base+"-"+side.suffix, cluster.Map{
				"capacity": cluster.Map{"storage": "64Mi"}, "accessModes": []interface{}{"ReadWriteMany"}, "persistentVolumeReclaimPolicy": "Retain", "storageClassName": "",
				"hostPath":     cluster.Map{"path": "/var/lib/rknetes/pigeon-spool/" + uid, "type": "DirectoryOrCreate"},
				"claimRef":     cluster.Map{"namespace": side.ns, "name": claimName},
				"nodeAffinity": cluster.Map{"required": cluster.Map{"nodeSelectorTerms": []interface{}{cluster.Map{"matchExpressions": []interface{}{cluster.Map{"key": "kubernetes.io/hostname", "operator": "In", "values": []interface{}{node}}}}}}},
			}), uid)
			if err := r.immutable(ctx, "persistentvolumes", pv); err != nil {
				return err
			}
			claim := owned(cluster.NewObject("v1", "PersistentVolumeClaim", side.ns, claimName, cluster.Map{"accessModes": []interface{}{"ReadWriteMany"}, "resources": cluster.Map{"requests": cluster.Map{"storage": "64Mi"}}, "storageClassName": "", "volumeName": base + "-" + side.suffix}), uid)
			if err := r.immutable(ctx, "persistentvolumeclaims", claim); err != nil {
				return err
			}
			pod := owned(cluster.NewObject("v1", "Pod", side.ns, p.GetName(), cluster.Map{
				"nodeName": node, "automountServiceAccountToken": false,
				"initContainers": []interface{}{cluster.Map{"name": "binary", "image": image, "command": []interface{}{"sh", "-ec", `curl -fsS "$1" -o /rk/pigeon; echo "$2  /rk/pigeon" | sha256sum -c -; chmod +x /rk/pigeon`, "download", url, hash}, "volumeMounts": []interface{}{cluster.Map{"name": "bin", "mountPath": "/rk"}}}},
				"containers": []interface{}{cluster.Map{"name": "pigeon", "image": image, "command": []interface{}{"/rk/pigeon", "--source", side.ns, "--destination", side.peer, "--tun-address", side.address, "--tun-peer", side.peerIP, fmt.Sprintf("--delay=%ds", cluster.Int(p.Object, 180, "spec", "delaySeconds")), fmt.Sprintf("--loss=%d", cluster.Int(p.Object, 55, "spec", "lossPercent"))},
					"securityContext": cluster.Map{"privileged": true}, "resources": cluster.Map{"requests": cluster.Map{"cpu": "20m", "memory": "32Mi"}, "limits": cluster.Map{"cpu": "1", "memory": "128Mi"}},
					"readinessProbe": cluster.Map{"exec": cluster.Map{"command": []interface{}{"ip", "link", "show", "pigeon0"}}, "periodSeconds": int64(1)},
					"volumeMounts":   []interface{}{cluster.Map{"name": "bin", "mountPath": "/rk"}, cluster.Map{"name": "spool", "mountPath": "/spool"}}}},
				"volumes": []interface{}{cluster.Map{"name": "bin", "emptyDir": cluster.Map{}}, cluster.Map{"name": "spool", "persistentVolumeClaim": cluster.Map{"claimName": claimName}}},
			}), uid)
			if err := r.pod(ctx, pod); err != nil {
				return err
			}
			if current, err := r.C.R("pods", side.ns).Get(ctx, p.GetName(), metav1.GetOptions{}); err == nil {
				cs, _, _ := unstructured.NestedSlice(current.Object, "status", "conditions")
				for _, v := range cs {
					c := v.(map[string]interface{})
					if c["type"] == "Ready" && c["status"] == "True" {
						ready++
					}
				}
			}
		}
		state := "False"
		if ready == 2 {
			state = "True"
		}
		var received int64
		if ready == 2 && cluster.Bool(p.Object, "spec", "observeTraffic") {
			var stats struct {
				Injected int64 `json:"injected"`
			}
			if err := r.podJSON(ctx, destination, p.GetName(), 7778, "/stats", &stats); err == nil {
				received = stats.Injected
			}
		}
		if err := r.C.Status(ctx, "pigeons", p, cluster.Map{"destinationNamespace": destination, "destinationUID": string(target.GetUID()), "nodeName": node, "claimName": claimName, "readyEndpoints": ready, "receivedPackets": received, "conditions": conditions(cluster.Condition("Ready", state, "CarrierEndpointsObserved", "Two TUN endpoints carry benchmark-range packets through a shared PVC"))}); err != nil {
			return err
		}
	}
	return nil
}
