package controller

import (
	"context"
	"fmt"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"rknetes.su/rknetes/pkg/cluster"
	"time"
)

// Disclosure is an explicit contract for keys generated outside Kubernetes:
// a Pod declares that disclosure is required and names its exported TLS Secret.
// The controller cannot infer private keys from opaque process memory.
func (r *Controller) Disclosure(ctx context.Context, ns string) error {
	pods, err := r.C.List(ctx, "pods", ns)
	if err != nil {
		return err
	}
	for i := range pods {
		pod := &pods[i]
		if pod.GetAnnotations()["rknetes.su/tls-disclosure-required"] != "true" || pod.GetDeletionTimestamp() != nil {
			continue
		}
		name := pod.GetAnnotations()["rknetes.su/key-escrow-secret"]
		disclosed := false
		if name != "" {
			s, err := r.C.R("secrets", ns).Get(ctx, name, metav1.GetOptions{})
			if err == nil && cluster.String(s.Object, "type") == "kubernetes.io/tls" && cluster.String(s.Object, "data", "tls.key") != "" {
				copy, err := r.C.R("secrets", "sorm").Get(ctx, "escrow-"+string(s.GetUID()), metav1.GetOptions{})
				disclosed = err == nil && cluster.String(copy.Object, "data", "tls.key") == cluster.String(s.Object, "data", "tls.key")
			}
		}
		state, reason, message := "True", "RefusedToShareKeys", "Declared TLS key has not been exported to a successfully escrowed Secret"
		if disclosed {
			state, reason, message = "False", "KeysDeposited", "Declared TLS key is present in the SORM copy; registry amnesty remains a separate procedure"
		}
		cs, _, _ := unstructured.NestedSlice(pod.Object, "status", "conditions")
		updated := []interface{}{}
		unchanged := false
		for _, v := range cs {
			c, ok := v.(map[string]interface{})
			if ok && c["type"] == "RefusedToShareKeys" {
				unchanged = c["status"] == state && c["reason"] == reason
				continue
			}
			updated = append(updated, v)
		}
		if !unchanged {
			c := cluster.Condition("RefusedToShareKeys", state, reason, message)
			c["lastTransitionTime"] = time.Now().UTC().Format(time.RFC3339)
			updated = append(updated, c)
			if err := r.C.Patch(ctx, "pods", ns, pod.GetName(), cluster.Map{"metadata": cluster.Map{"resourceVersion": pod.GetResourceVersion()}, "status": cluster.Map{"conditions": updated}}, "status"); err != nil {
				return err
			}
		}
		if !disclosed {
			entry := cluster.NewObject("rknetes.su/v1alpha1", "ReestrEntry", ns, "key-refusal-"+string(pod.GetUID()), cluster.Map{"podName": pod.GetName(), "reason": "RefusedToShareKeys", "escalate": true})
			entry.SetAnnotations(map[string]string{"rknetes.su/disclosure-contract": fmt.Sprintf("Pod/%s requires an exported TLS Secret", pod.GetName())})
			if err := r.C.Apply(ctx, "reestrentries", entry); err != nil {
				return err
			}
		}
	}
	return nil
}
