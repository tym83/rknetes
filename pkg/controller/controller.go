package controller

import (
	"context"
	"log"
	"rknetes.su/rknetes/pkg/cluster"
	"time"
)

type Controller struct {
	C         *cluster.Client
	Namespace string
}

func (r *Controller) Run(ctx context.Context) error {
	if err := r.C.Guard(ctx); err != nil {
		return err
	}
	tick := time.NewTicker(2 * time.Second)
	defer tick.Stop()
	for {
		namespaces, err := r.C.List(ctx, "namespaces", "")
		if err != nil {
			log.Printf("namespace reconciliation: %v", err)
		}
		for _, ns := range namespaces {
			if (r.Namespace != "" && ns.GetName() != r.Namespace) || (r.Namespace == "" && ns.GetLabels()["rknetes.su/independent-controller"] == "true") {
				continue
			}
			if ns.GetLabels()["rknetes.su/lab"] != "true" {
				continue
			}
			for _, step := range []struct {
				name string
				run  func(context.Context, string) error
			}{
				{"reestr", r.Reestr}, {"throttle", r.Throttle}, {"whitelist", r.Whitelist}, {"werewolf", r.Werewolf},
				{"pigeon", r.Pigeons}, {"tunnels", r.Tunnels}, {"measurements", r.Measurements}, {"archive", r.Archives}, {"escrow", r.Escrow}, {"drill", r.Drill}, {"roaming", r.Roaming}, {"cooling", r.Cooling}, {"statement", r.Statement},
			} {
				if err := step.run(ctx, ns.GetName()); err != nil {
					log.Printf("%s/%s: %v", ns.GetName(), step.name, err)
				}
			}
		}
		select {
		case <-ctx.Done():
			return nil
		case <-tick.C:
		}
	}
}
func conditions(cs ...cluster.Map) []interface{} {
	out := make([]interface{}, len(cs))
	for i, c := range cs {
		out[i] = c
	}
	return out
}
func (r *Controller) event(ctx context.Context, ns, name, kind, reason, message string) error {
	// A deterministic event name bounds repeated official statements.
	o := cluster.NewObject("v1", "Event", ns, name, nil)
	delete(o.Object, "spec")
	o.Object["involvedObject"] = cluster.Map{"apiVersion": "rknetes.su/v1alpha1", "kind": kind, "namespace": ns, "name": name}
	o.Object["reason"] = reason
	o.Object["message"] = message
	o.Object["type"] = "Normal"
	o.Object["source"] = cluster.Map{"component": "rknet-controller"}
	return r.C.Apply(ctx, "events", o)
}
func (r *Controller) cnp(ctx context.Context, ns, name string, spec cluster.Map, owner *cluster.Object) error {
	o := cluster.NewObject("cilium.io/v2", "CiliumNetworkPolicy", ns, name, spec)
	if owner != nil {
		o.Object["metadata"].(cluster.Map)["ownerReferences"] = []interface{}{cluster.Map{"apiVersion": owner.GetAPIVersion(), "kind": owner.GetKind(), "name": owner.GetName(), "uid": string(owner.GetUID())}}
	}
	return r.C.Apply(ctx, "ciliumnetworkpolicies", o)
}
