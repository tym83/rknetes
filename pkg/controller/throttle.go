package controller

import (
	"context"
	"k8s.io/apimachinery/pkg/api/resource"
	"regexp"
	"rknetes.su/rknetes/pkg/cluster"
)

func (r *Controller) Throttle(ctx context.Context, ns string) error {
	policies, err := r.C.List(ctx, "throttlepolicies", ns)
	if err != nil {
		return err
	}
	pods, err := r.C.List(ctx, "pods", ns)
	if err != nil {
		return err
	}
	for i := range policies {
		p := &policies[i]
		pattern, err := regexp.Compile(cluster.String(p.Object, "spec", "pattern"))
		if err != nil {
			return err
		}
		rate := cluster.String(p.Object, "spec", "bandwidth")
		if _, err := resource.ParseQuantity(rate); err != nil {
			return err
		}
		affected := []interface{}{}
		for _, pod := range pods {
			if !pattern.MatchString(pod.GetName()) && !pattern.MatchString(pod.GetAnnotations()["rknetes.su/domain"]) {
				continue
			}
			affected = append(affected, pod.GetName())
			if pod.GetAnnotations()["kubernetes.io/egress-bandwidth"] == rate {
				continue
			}
			if err := r.C.Patch(ctx, "pods", ns, pod.GetName(), cluster.Map{"metadata": cluster.Map{"annotations": cluster.Map{"kubernetes.io/egress-bandwidth": rate}}}); err != nil {
				return err
			}
		}
		if err := r.C.Status(ctx, "throttlepolicies", p, cluster.Map{"affectedPods": affected, "conditions": conditions(cluster.Condition("Applied", "True", "BandwidthAnnotated", "Cilium bandwidth manager enforces the configured pod egress rate"))}); err != nil {
			return err
		}
		if err := r.event(ctx, ns, p.GetName(), p.GetKind(), "NotRelated", "С действиями регулятора неполадки не связаны"); err != nil {
			return err
		}
	}
	return nil
}
