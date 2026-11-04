package controller

import (
	"context"
	"fmt"
	"net/netip"

	"rknetes.su/rknetes/pkg/cluster"
)

// Werewolf exposes the unmodified Service externalIPs mechanism in the lab.
func (r *Controller) Werewolf(ctx context.Context, ns string) error {
	wolves, err := r.C.List(ctx, "werewolves", ns)
	if err != nil {
		return err
	}
	for i := range wolves {
		wolf := &wolves[i]
		address := cluster.String(wolf.Object, "spec", "address")
		ip, err := netip.ParseAddr(address)
		if err != nil || !netip.MustParsePrefix("10.96.0.0/12").Contains(ip) {
			return fmt.Errorf("werewolf address must be in the nested Service CIDR")
		}
		selector := cluster.Labels(wolf.Object, "spec", "selector")
		if len(selector) == 0 {
			return fmt.Errorf("werewolf requires a target selector")
		}
		labels := cluster.Map{}
		for k, v := range selector {
			labels[k] = v
		}
		port := cluster.Int(wolf.Object, 8080, "spec", "port")
		service := cluster.NewObject("v1", "Service", ns, wolf.GetName(), cluster.Map{
			"selector": labels, "externalIPs": []interface{}{address},
			"ports": []interface{}{cluster.Map{"name": "http", "port": port, "targetPort": port, "protocol": "TCP"}},
		})
		if err := r.C.Apply(ctx, "services", service); err != nil {
			return err
		}
		if err := r.C.Status(ctx, "werewolves", wolf, cluster.Map{"conditions": conditions(cluster.Condition("Applied", "True", "ExternalIPClaimed", "Service externalIPs installed; reachability is measured separately"))}); err != nil {
			return err
		}
	}
	return nil
}
