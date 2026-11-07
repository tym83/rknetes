package controller

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"rknetes.su/rknetes/pkg/cluster"
)

func (r *Controller) quarterly(ctx context.Context, p *cluster.Object) error {
	if !cluster.Bool(p.Object, "spec", "quarterly") {
		return nil
	}
	ns := p.GetNamespace()
	uid := string(p.GetUID())
	name := "drill-" + uid
	namespace, err := r.C.R("namespaces", "").Get(ctx, ns, metav1.GetOptions{})
	if err != nil {
		return err
	}
	url, hash, image, err := r.artifact(ctx, "drill-trigger")
	if err != nil {
		return err
	}
	duration := cluster.Int(p.Object, 300, "spec", "durationSeconds")
	if duration < 1 || duration > 3600 {
		return fmt.Errorf("drill duration must be1..3600seconds")
	}
	owner := []metav1.OwnerReference{{APIVersion: p.GetAPIVersion(), Kind: p.GetKind(), Name: p.GetName(), UID: p.GetUID()}}
	account := owned(cluster.NewObject("v1", "ServiceAccount", ns, name, nil), uid)
	delete(account.Object, "spec")
	account.SetOwnerReferences(owner)
	if err := r.C.Apply(ctx, "serviceaccounts", account); err != nil {
		return err
	}
	role := owned(cluster.NewObject("rbac.authorization.k8s.io/v1", "Role", ns, name, nil), uid)
	delete(role.Object, "spec")
	role.SetOwnerReferences(owner)
	role.Object["rules"] = []interface{}{cluster.Map{"apiGroups": []interface{}{"rknetes.su"}, "resources": []interface{}{"sovereigntydrills"}, "resourceNames": []interface{}{p.GetName()}, "verbs": []interface{}{"patch"}}}
	if err := r.C.Apply(ctx, "roles", role); err != nil {
		return err
	}
	bind := owned(cluster.NewObject("rbac.authorization.k8s.io/v1", "RoleBinding", ns, name, nil), uid)
	delete(bind.Object, "spec")
	bind.SetOwnerReferences(owner)
	bind.Object["roleRef"] = cluster.Map{"apiGroup": "rbac.authorization.k8s.io", "kind": "Role", "name": name}
	bind.Object["subjects"] = []interface{}{cluster.Map{"kind": "ServiceAccount", "namespace": ns, "name": name}}
	if err := r.C.Apply(ctx, "rolebindings", bind); err != nil {
		return err
	}
	clusterOwner := []metav1.OwnerReference{{APIVersion: "v1", Kind: "Namespace", Name: ns, UID: namespace.GetUID()}}
	marker := owned(cluster.NewObject("rbac.authorization.k8s.io/v1", "ClusterRole", "", name, nil), uid)
	delete(marker.Object, "spec")
	marker.SetOwnerReferences(clusterOwner)
	marker.Object["rules"] = []interface{}{cluster.Map{"apiGroups": []interface{}{""}, "resources": []interface{}{"configmaps"}, "resourceNames": []interface{}{"rknetes-stand"}, "verbs": []interface{}{"get"}}}
	if err := r.C.Apply(ctx, "clusterroles", marker); err != nil {
		return err
	}
	markerBind := owned(cluster.NewObject("rbac.authorization.k8s.io/v1", "ClusterRoleBinding", "", name, nil), uid)
	delete(markerBind.Object, "spec")
	markerBind.SetOwnerReferences(clusterOwner)
	markerBind.Object["roleRef"] = cluster.Map{"apiGroup": "rbac.authorization.k8s.io", "kind": "ClusterRole", "name": name}
	markerBind.Object["subjects"] = bind.Object["subjects"]
	if err := r.C.Apply(ctx, "clusterrolebindings", markerBind); err != nil {
		return err
	}
	job := owned(cluster.NewObject("batch/v1", "CronJob", ns, name, cluster.Map{
		"schedule": "0 3 1 */3 *", "timeZone": "Etc/UTC", "concurrencyPolicy": "Forbid", "startingDeadlineSeconds": int64(3600), "successfulJobsHistoryLimit": int64(1), "failedJobsHistoryLimit": int64(1),
		"jobTemplate": cluster.Map{"spec": cluster.Map{"backoffLimit": int64(0), "activeDeadlineSeconds": duration + 90, "template": cluster.Map{"spec": cluster.Map{
			"serviceAccountName": name, "restartPolicy": "Never",
			"initContainers": []interface{}{cluster.Map{"name": "binary", "image": image, "command": []interface{}{"sh", "-ec", `curl -fsS "$1" -o /rk/drill-trigger; echo "$2  /rk/drill-trigger" | sha256sum -c -; chmod +x /rk/drill-trigger`, "download", url, hash}, "volumeMounts": []interface{}{cluster.Map{"name": "bin", "mountPath": "/rk"}}}},
			"containers":     []interface{}{cluster.Map{"name": "drill", "image": image, "command": []interface{}{"/rk/drill-trigger", "--namespace", ns, "--name", p.GetName(), fmt.Sprintf("--duration=%ds", duration)}, "volumeMounts": []interface{}{cluster.Map{"name": "bin", "mountPath": "/rk"}}}}, "volumes": []interface{}{cluster.Map{"name": "bin", "emptyDir": cluster.Map{}}},
		}}}},
	}), uid)
	job.SetOwnerReferences(owner)
	encoded, _ := json.Marshal(job.Object["spec"])
	digest := sha256.Sum256(encoded)
	hashAnnotation := hex.EncodeToString(digest[:])
	job.SetAnnotations(map[string]string{"rknetes.su/template-sha256": hashAnnotation})
	old, err := r.C.R("cronjobs", ns).Get(ctx, name, metav1.GetOptions{})
	if err == nil {
		if old.GetLabels()["rknetes.su/owner"] != uid {
			return fmt.Errorf("unrelated scheduled drill")
		}
		if old.GetAnnotations()["rknetes.su/template-sha256"] == hashAnnotation {
			return nil
		}
	} else if !apierrors.IsNotFound(err) {
		return err
	}
	return r.C.Apply(ctx, "cronjobs", job)
}
