package controller

import (
	"context"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"net/netip"
	"rknetes.su/rknetes/pkg/cluster"
	"slices"
	"time"
)

func (r *Controller) Reestr(ctx context.Context, ns string) error {
	entries, err := r.C.List(ctx, "reestrentries", ns)
	if err != nil {
		return err
	}
	pods, err := r.C.List(ctx, "pods", ns)
	if err != nil {
		return err
	}
	for i := range entries {
		e := &entries[i]
		history := cluster.Strings(e.Object, "status", "addresses")
		origin := cluster.Labels(e.Object, "status", "originalOwners")
		if origin == nil {
			origin = map[string]string{}
		}
		cidrs := cluster.Strings(e.Object, "status", "cidrs")
		amnesty := false
		for j := range pods {
			p := &pods[j]
			if p.GetName() != cluster.String(e.Object, "spec", "podName") && (len(cluster.Labels(e.Object, "spec", "selector")) == 0 || !cluster.Match(p.GetLabels(), cluster.Labels(e.Object, "spec", "selector"))) {
				continue
			}
			if p.GetAnnotations()["rknetes.su/ready-to-counter-terrorism"] == "true" {
				amnesty = true
				continue
			}
			ip := cluster.String(p.Object, "status", "podIP")
			if ip == "" {
				continue
			}
			if !slices.Contains(history, ip) {
				history = append(history, ip)
				origin[ip] = string(p.GetUID())
			}
			prefix, parseErr := netip.ParseAddr(ip)
			if parseErr != nil {
				return parseErr
			}
			host := netip.PrefixFrom(prefix, prefix.BitLen()).String()
			if !slices.Contains(cidrs, host) {
				cidrs = append(cidrs, host)
			}
			if cluster.Bool(e.Object, "spec", "escalate") {
				age := time.Since(e.GetCreationTimestamp().Time)
				if age >= time.Duration(cluster.Int(e.Object, 1200, "spec", "nodeAfterSeconds"))*time.Second {
					node, err := r.C.R("nodes", "").Get(ctx, cluster.String(p.Object, "spec", "nodeName"), metav1.GetOptions{})
					if err != nil {
						return err
					}
					cidr := cluster.String(node.Object, "spec", "podCIDR")
					if cidr != "" && !slices.Contains(cidrs, cidr) {
						cidrs = append(cidrs, cidr)
					}
				}
				if age >= time.Duration(cluster.Int(e.Object, 4800, "spec", "poolAfterSeconds"))*time.Second && !slices.Contains(cidrs, "10.42.0.0/16") {
					cidrs = append(cidrs, "10.42.0.0/16")
				}
			}
			if cluster.Bool(e.Object, "spec", "forever") && !slices.Contains(p.GetFinalizers(), "rknetes.su/forever") {
				if err := r.C.Patch(ctx, "pods", ns, p.GetName(), cluster.Map{"metadata": cluster.Map{"finalizers": append(p.GetFinalizers(), "rknetes.su/forever")}}); err != nil {
					return err
				}
			}
		}
		policyName := "reestr-" + e.GetName()
		if amnesty {
			err := r.C.R("ciliumnetworkpolicies", ns).Delete(ctx, policyName, metav1.DeleteOptions{})
			if err != nil && !apierrors.IsNotFound(err) {
				return err
			}
			if err := r.C.Status(ctx, "reestrentries", e, cluster.Map{"conditions": conditions(cluster.Condition("Applied", "False", "Amnesty", "Готовность противодействовать терроризму подтверждена аннотацией"))}); err != nil {
				return err
			}
			continue
		}
		deny := []interface{}{}
		for _, ip := range cidrs {
			deny = append(deny, cluster.Map{"cidr": ip})
		}
		spec := cluster.Map{"endpointSelector": cluster.Map{}, "enableDefaultDeny": cluster.Map{"ingress": false, "egress": false}}
		if len(deny) > 0 {
			spec["egressDeny"] = []interface{}{cluster.Map{"toCIDRSet": deny}}
			spec["ingressDeny"] = []interface{}{cluster.Map{"fromCIDRSet": deny}}
		}
		serviceAfter := cluster.Int(e.Object, 0, "spec", "serviceAfterSeconds")
		if serviceAfter > 0 && time.Since(e.GetCreationTimestamp().Time) >= time.Duration(serviceAfter)*time.Second {
			// Service DNAT resolves the API's identity before policy evaluation.
			// Deny that identity as well as the original Service CIDR.
			deny = append(deny, cluster.Map{"cidr": "10.96.0.0/12"})
			spec["egressDeny"] = []interface{}{cluster.Map{"toCIDRSet": deny}, cluster.Map{"toEntities": []interface{}{"kube-apiserver"}}}
			if !slices.Contains(cidrs, "10.96.0.0/12") {
				cidrs = append(cidrs, "10.96.0.0/12")
			}
		}
		if err := r.cnp(ctx, ns, policyName, spec, e); err != nil {
			return err
		}
		owners := cluster.Map{}
		for k, v := range origin {
			owners[k] = v
		}
		ips := make([]interface{}, len(history))
		for i, v := range history {
			ips[i] = v
		}
		ranges := make([]interface{}, len(cidrs))
		for i, v := range cidrs {
			ranges[i] = v
		}
		if err := r.C.Status(ctx, "reestrentries", e, cluster.Map{"addresses": ips, "cidrs": ranges, "originalOwners": owners, "conditions": conditions(cluster.Condition("Applied", "True", "PolicyInstalled", "IP policy installed; packet reachability is measured by e2e probes"))}); err != nil {
			return err
		}
		for j := range pods {
			p := &pods[j]
			ip := cluster.String(p.Object, "status", "podIP")
			if origin[ip] == "" || origin[ip] == string(p.GetUID()) {
				continue
			}
			cs, _, _ := unstructured.NestedSlice(p.Object, "status", "conditions")
			found := false
			for _, c := range cs {
				if m, ok := c.(map[string]interface{}); ok && m["type"] == "BornBlocked" {
					found = true
				}
			}
			if found {
				continue
			}
			c := cluster.Condition("BornBlocked", "True", "InheritedFromPreviousTenant", "IP inherited from a registered predecessor")
			c["lastTransitionTime"] = time.Now().UTC().Format(time.RFC3339)
			cs = append(cs, c)
			if err := r.C.Patch(ctx, "pods", ns, p.GetName(), cluster.Map{"status": cluster.Map{"conditions": cs}}, "status"); err != nil {
				return err
			}
		}
	}
	return nil
}
