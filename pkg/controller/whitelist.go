package controller

import (
	"context"
	"fmt"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"rknetes.su/rknetes/pkg/cluster"
	"slices"
	"sort"
)

func (r *Controller) Whitelist(ctx context.Context, ns string) error {
	modes, err := r.C.List(ctx, "whitelistmodes", ns)
	if err != nil {
		return err
	}
	social, err := r.C.List(ctx, "sociallysignificantresources", ns)
	if err != nil {
		return err
	}
	pods, err := r.C.List(ctx, "pods", ns)
	if err != nil {
		return err
	}
	endpoints, err := r.C.List(ctx, "endpointslices", ns)
	if err != nil {
		return err
	}
	services, err := r.C.List(ctx, "services", ns)
	if err != nil {
		return err
	}
	sort.Slice(social, func(i, j int) bool {
		return social[i].GetCreationTimestamp().Time.Before(social[j].GetCreationTimestamp().Time)
	})
	enabled, integrity := false, false
	for _, m := range modes {
		enabled = enabled || cluster.Bool(m.Object, "spec", "enabled")
		integrity = integrity || cluster.Bool(m.Object, "spec", "integrity")
	}
	if !enabled {
		for _, name := range []string{"whitelist", "whitelist-integrity"} {
			err := r.C.R("ciliumnetworkpolicies", ns).Delete(ctx, name, metav1.DeleteOptions{})
			if err != nil && !apierrors.IsNotFound(err) {
				return err
			}
		}
		return nil
	}
	allowed := []interface{}{}
	denied := []interface{}{}
	for i := range social {
		s := &social[i]
		if !cluster.Bool(s.Object, "spec", "approved") {
			continue
		}
		selector := cluster.Labels(s.Object, "spec", "selector")
		if len(selector) == 0 {
			return fmt.Errorf("social resource %s has an empty selector", s.GetName())
		}
		selected := map[string]bool{}
		violations := []interface{}{}
		accounts := cluster.Strings(s.Object, "spec", "allowedServiceAccounts")
		images := cluster.Strings(s.Object, "spec", "allowedImages")
		for _, p := range pods {
			if !cluster.Match(p.GetLabels(), selector) {
				continue
			}
			ip := cluster.String(p.Object, "status", "podIP")
			selected[ip] = true
			if len(accounts) > 0 && !slices.Contains(accounts, cluster.String(p.Object, "spec", "serviceAccountName")) {
				violations = append(violations, "ServiceAccountSpoof:"+p.GetName())
			}
			if ecs, _, _ := unstructured.NestedSlice(p.Object, "spec", "ephemeralContainers"); len(ecs) > 0 {
				violations = append(violations, "EphemeralContainer:"+p.GetName())
			}
			containers, _, _ := unstructured.NestedSlice(p.Object, "spec", "containers")
			for _, c := range containers {
				if len(images) > 0 && !slices.Contains(images, cluster.String(c.(map[string]interface{}), "image")) {
					violations = append(violations, "ImageSpoof:"+p.GetName())
				}
			}
		}
		for _, e := range endpoints {
			if e.GetLabels()["kubernetes.io/service-name"] != cluster.String(s.Object, "spec", "serviceName") {
				continue
			}
			es, _, _ := unstructured.NestedSlice(e.Object, "endpoints")
			for _, x := range es {
				for _, a := range cluster.Strings(x.(map[string]interface{}), "addresses") {
					if !selected[a] {
						violations = append(violations, "EndpointSliceHijack:"+e.GetName()+":"+a)
					}
				}
			}
			if e.GetLabels()["endpointslice.kubernetes.io/managed-by"] != "endpointslice-controller.k8s.io" {
				violations = append(violations, "ManualEndpointSlice:"+e.GetName())
			}
		}
		for _, svc := range services {
			if svc.GetName() == cluster.String(s.Object, "spec", "serviceName") {
				continue
			}
			for _, external := range cluster.Strings(svc.Object, "spec", "externalIPs") {
				for _, target := range services {
					if target.GetName() == cluster.String(s.Object, "spec", "serviceName") && external == cluster.String(target.Object, "spec", "clusterIP") {
						violations = append(violations, "ExternalIPHijack:"+svc.GetName())
					}
				}
			}
		}
		match := cluster.Map{}
		for k, v := range selector {
			match[k] = v
		}
		endpoint := cluster.Map{"matchLabels": match}
		whitelisted, reason := "True", "Approved"
		if integrity && len(violations) > 0 {
			denied = append(denied, endpoint)
			whitelisted, reason = "False", "IntegrityViolation"
		} else {
			allowed = append(allowed, endpoint)
		}
		if err := r.C.Status(ctx, "sociallysignificantresources", s, cluster.Map{"violations": violations, "conditions": conditions(cluster.Condition("Whitelisted", whitelisted, reason, "Decision applies to the service and all matching endpoints"), cluster.Condition("ActuallyReachable", "Unknown", "DependencyGraphNotInScope", "Проверка зависимостей не входит в компетенцию ведомства"))}); err != nil {
			return err
		}
	}
	egress := []interface{}{}
	if len(allowed) > 0 {
		egress = append(egress, cluster.Map{"toEndpoints": allowed})
	}
	// DNS remains reachable so dependency failures can be distinguished from lookup failures.
	egress = append(egress, cluster.Map{"toEndpoints": []interface{}{cluster.Map{"matchLabels": cluster.Map{"k8s:io.kubernetes.pod.namespace": "kube-system", "k8s:k8s-app": "kube-dns"}}}, "toPorts": []interface{}{cluster.Map{"ports": []interface{}{cluster.Map{"port": "53", "protocol": "ANY"}}}}})
	if err := r.cnp(ctx, ns, "whitelist", cluster.Map{"endpointSelector": cluster.Map{}, "egress": egress}, nil); err != nil {
		return err
	}
	if len(denied) > 0 {
		return r.cnp(ctx, ns, "whitelist-integrity", cluster.Map{"endpointSelector": cluster.Map{}, "egressDeny": []interface{}{cluster.Map{"toEndpoints": denied}}}, nil)
	}
	err = r.C.R("ciliumnetworkpolicies", ns).Delete(ctx, "whitelist-integrity", metav1.DeleteOptions{})
	if apierrors.IsNotFound(err) {
		return nil
	}
	return err
}
