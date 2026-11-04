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
	"strconv"
	"time"
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
		left, right := social[i].GetCreationTimestamp(), social[j].GetCreationTimestamp()
		if left.Equal(&right) {
			return social[i].GetName() < social[j].GetName()
		}
		return social[i].GetCreationTimestamp().Time.Before(social[j].GetCreationTimestamp().Time)
	})
	enabled, integrity := false, false
	capacity := int64(0)
	for i := range modes {
		m := &modes[i]
		active := cluster.Bool(m.Object, "spec", "enabled")
		period := cluster.Int(m.Object, 0, "spec", "periodSeconds")
		if period > 0 && (period < 10 || period > 31536000) {
			return fmt.Errorf("whitelist period must be 10..31536000 seconds")
		}
		if period > 0 {
			active = active && time.Since(m.GetCreationTimestamp().Time).Milliseconds()%(period*1000) < period*cluster.Int(m.Object, 60, "spec", "activePercent")*10
		}
		enabled = enabled || active
		integrity = integrity || cluster.Bool(m.Object, "spec", "integrity")
		if measurement := cluster.String(m.Object, "spec", "capacityMeasurement"); measurement != "" {
			cm, err := r.C.R("configmaps", ns).Get(ctx, measurement, metav1.GetOptions{})
			if err != nil {
				return err
			}
			maxEntries, err := strconv.ParseInt(cluster.String(cm.Object, "data", "maxEntries"), 10, 64)
			reserved := cluster.Int(m.Object, 0, "spec", "reservedEntries")
			if err != nil || maxEntries <= reserved || cm.GetLabels()["rknetes.su/managed"] != "true" || cluster.String(cm.Object, "data", "kind") != "cilium-policy-map" {
				return fmt.Errorf("invalid measured Cilium capacity")
			}
			available := maxEntries - reserved
			if requested := cluster.Int(m.Object, 0, "spec", "capacity"); requested > 0 && requested < available {
				available = requested
			}
			if capacity == 0 || available < capacity {
				capacity = available
			}
		}
		state := "False"
		if active {
			state = "True"
		}
		if err := r.C.Status(ctx, "whitelistmodes", m, cluster.Map{"admissionCapacity": capacity, "conditions": conditions(cluster.Condition("Active", state, "ScheduledDecision", "The admission queue is distinct from the measured kernel map"))}); err != nil {
			return err
		}
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
	approved := []string{}
	for _, s := range social {
		if cluster.Bool(s.Object, "spec", "approved") {
			approved = append(approved, s.GetName())
		}
	}
	evicted := map[string]bool{}
	if capacity > 0 && int64(len(approved)) > capacity {
		for _, name := range approved[:int64(len(approved))-capacity] {
			evicted[name] = true
		}
	}
	for i := range social {
		s := &social[i]
		if !cluster.Bool(s.Object, "spec", "approved") {
			continue
		}
		if evicted[s.GetName()] {
			if err := r.C.Status(ctx, "sociallysignificantresources", s, cluster.Map{"conditions": conditions(cluster.Condition("Whitelisted", "False", "AdmissionQueueCapacity", "UnderReview: the oldest approval left the admission queue; the kernel did not evict it"), cluster.Condition("ActuallyReachable", "Unknown", "DependencyGraphNotInScope", "Проверка зависимостей не входит в компетенцию ведомства"))}); err != nil {
				return err
			}
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
