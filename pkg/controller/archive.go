package controller

import (
	"context"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"rknetes.su/rknetes/pkg/cluster"
	"sort"
)

// Archives grants only the lab collector reads and ArchivePolicy status writes.
func (r *Controller) Archives(ctx context.Context, ns string) error {
	policies, err := r.C.List(ctx, "archivepolicies", ns)
	if err != nil || len(policies) == 0 {
		return err
	}
	namespace, err := r.C.R("namespaces", "").Get(ctx, ns, metav1.GetOptions{})
	if err != nil {
		return err
	}
	owner := []metav1.OwnerReference{{APIVersion: "v1", Kind: "Namespace", Name: ns, UID: namespace.GetUID()}}
	name := "archive-" + string(namespace.GetUID())
	role := cluster.NewObject("rbac.authorization.k8s.io/v1", "Role", ns, name, nil)
	delete(role.Object, "spec")
	role.SetOwnerReferences(owner)
	role.Object["rules"] = []interface{}{cluster.Map{"apiGroups": []interface{}{""}, "resources": []interface{}{"pods"}, "verbs": []interface{}{"get", "list"}}, cluster.Map{"apiGroups": []interface{}{"rknetes.su"}, "resources": []interface{}{"archivepolicies"}, "verbs": []interface{}{"get"}}, cluster.Map{"apiGroups": []interface{}{"rknetes.su"}, "resources": []interface{}{"archivepolicies/status"}, "verbs": []interface{}{"patch"}}}
	if err := r.C.Apply(ctx, "roles", role); err != nil {
		return err
	}
	accounts := map[string]bool{"default": true}
	pods, err := r.C.List(ctx, "pods", ns)
	if err != nil {
		return err
	}
	for _, pod := range pods {
		accounts[cluster.String(pod.Object, "spec", "serviceAccountName")] = true
	}
	subjects := []interface{}{}
	names := []string{}
	for account := range accounts {
		names = append(names, account)
	}
	sort.Strings(names)
	for _, account := range names {
		if account != "" {
			subjects = append(subjects, cluster.Map{"kind": "ServiceAccount", "name": account, "namespace": ns})
		}
	}
	binding := cluster.NewObject("rbac.authorization.k8s.io/v1", "RoleBinding", ns, name, nil)
	delete(binding.Object, "spec")
	binding.SetOwnerReferences(owner)
	binding.Object["roleRef"] = cluster.Map{"apiGroup": "rbac.authorization.k8s.io", "kind": "Role", "name": name}
	binding.Object["subjects"] = subjects
	if err := r.C.Apply(ctx, "rolebindings", binding); err != nil {
		return err
	}
	marker := cluster.NewObject("rbac.authorization.k8s.io/v1", "ClusterRole", "", name, nil)
	delete(marker.Object, "spec")
	marker.SetOwnerReferences(owner)
	marker.Object["rules"] = []interface{}{cluster.Map{"apiGroups": []interface{}{""}, "resources": []interface{}{"namespaces"}, "resourceNames": []interface{}{ns}, "verbs": []interface{}{"get"}}, cluster.Map{"apiGroups": []interface{}{""}, "resources": []interface{}{"configmaps"}, "resourceNames": []interface{}{"rknetes-stand"}, "verbs": []interface{}{"get"}}}
	if err := r.C.Apply(ctx, "clusterroles", marker); err != nil {
		return err
	}
	global := cluster.NewObject("rbac.authorization.k8s.io/v1", "ClusterRoleBinding", "", name, nil)
	delete(global.Object, "spec")
	global.SetOwnerReferences(owner)
	global.Object["roleRef"] = cluster.Map{"apiGroup": "rbac.authorization.k8s.io", "kind": "ClusterRole", "name": name}
	global.Object["subjects"] = subjects
	return r.C.Apply(ctx, "clusterrolebindings", global)
}
