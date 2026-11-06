package controller

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/netip"
	"net/url"
	"strconv"
	"strings"
	"time"

	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/client-go/rest"
	"rknetes.su/rknetes/pkg/cluster"
)

// podJSON uses the authenticated API proxy, including when the controller runs
// outside the nested Pod network. Redirects and non-lab Pod addresses are refused.
func (r *Controller) podJSON(ctx context.Context, ns, name string, port int64, path string, output interface{}) error {
	namespace, err := r.C.R("namespaces", "").Get(ctx, ns, metav1.GetOptions{})
	if err != nil || namespace.GetLabels()["rknetes.su/lab"] != "true" {
		return fmt.Errorf("probe requires a labelled lab namespace")
	}
	pod, err := r.C.R("pods", ns).Get(ctx, name, metav1.GetOptions{})
	if err != nil {
		return err
	}
	ip, err := netip.ParseAddr(cluster.String(pod.Object, "status", "podIP"))
	if err != nil || !netip.MustParsePrefix("10.42.0.0/16").Contains(ip) || cluster.Bool(pod.Object, "spec", "hostNetwork") || port < 1024 || port > 65535 {
		return fmt.Errorf("probe requires an ordinary nested lab Pod and an unprivileged port")
	}
	client, err := rest.HTTPClientFor(r.C.Config)
	if err != nil {
		return err
	}
	client.Timeout = 5 * time.Second
	client.CheckRedirect = func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }
	u := strings.TrimRight(r.C.Config.Host, "/") + fmt.Sprintf("/api/v1/namespaces/%s/pods/%s:%d/proxy%s", ns, name, port, path)
	req, err := http.NewRequestWithContext(ctx, "GET", u, nil)
	if err != nil {
		return err
	}
	response, err := client.Do(req)
	if err != nil {
		return err
	}
	defer response.Body.Close()
	if response.StatusCode != 200 {
		return fmt.Errorf("lab probe returned HTTP %d", response.StatusCode)
	}
	return json.NewDecoder(io.LimitReader(response.Body, 4096)).Decode(output)
}

func (r *Controller) Tunnels(ctx context.Context, ns string) error {
	profiles, err := r.C.List(ctx, "tunnelprofiles", ns)
	if err != nil {
		return err
	}
	for i := range profiles {
		p := &profiles[i]
		if err := r.compliantTunnel(ctx, p); err != nil {
			return err
		}
		agent := cluster.String(p.Object, "spec", "agentPodName")
		ladder := cluster.Strings(p.Object, "spec", "protocolLadder")
		if agent == "" || len(ladder) == 0 || p.GetDeletionTimestamp() != nil {
			continue
		}
		index := cluster.Int(p.Object, 0, "status", "selectedIndex")
		if cluster.Int(p.Object, 0, "status", "observedGeneration") != p.GetGeneration() || index >= int64(len(ladder)) {
			index = 0
		}
		protocol := ladder[index]
		var result struct {
			Success bool  `json:"success"`
			Bytes   int64 `json:"bytes"`
		}
		message := "Actual protocol request failed"
		waiting := false
		if protocol == "Pigeon" {
			bird, getErr := r.C.R("pigeons", ns).Get(ctx, cluster.String(p.Object, "spec", "pigeonRef"), metav1.GetOptions{})
			if getErr == nil {
				result.Bytes = cluster.Int(bird.Object, 0, "status", "receivedPackets")
				result.Success = result.Bytes > 0
			}
			waiting = !result.Success
			message = "Waiting for real IP packets delivered by the carrier"
		} else {
			probeErr := r.podJSON(ctx, ns, agent, cluster.Int(p.Object, 7777, "spec", "agentPort"), "/probe?protocol="+url.QueryEscape(protocol), &result)
			if probeErr != nil {
				// A failed management channel is not evidence that a VPN failed.
				waiting = true
				message = probeErr.Error()
			}
		}
		state, reason := "False", "ProbeFailed"
		if result.Success {
			state, reason, message = "True", "TrafficObserved", "Переход на доступный протокол подтверждён настоящим трафиком"
		} else if waiting {
			reason = "ProbePending"
		} else {
			if err := r.countBlockedTunnel(ctx, p, index); err != nil {
				return err
			}
			if index+1 < int64(len(ladder)) {
				index++
			}
		}
		status, _, _ := unstructured.NestedMap(p.Object, "status")
		if status == nil {
			status = cluster.Map{}
		}
		status["selectedIndex"], status["activeProtocol"] = index, ladder[index]
		status["observedGeneration"], status["probeBytes"] = p.GetGeneration(), result.Bytes
		status["lastProbedProtocol"] = protocol
		status["conditions"] = conditions(cluster.Condition("Ready", state, reason, message))
		if err := r.C.Status(ctx, "tunnelprofiles", p, status); err != nil {
			return err
		}
	}
	return nil
}

// Persist the failure and the idempotency key in one optimistic API update.
// A restart, failed status write, or repeated failed probe cannot inflate it.
func (r *Controller) countBlockedTunnel(ctx context.Context, p *cluster.Object, index int64) error {
	ns := p.GetNamespace()
	cm, err := r.C.R("configmaps", ns).Get(ctx, "vpn-counters", metav1.GetOptions{})
	if apierrors.IsNotFound(err) {
		cm = cluster.NewObject("v1", "ConfigMap", ns, "vpn-counters", nil)
		delete(cm.Object, "spec")
		cm.Object["data"] = cluster.Map{"blocked": "0"}
		if err := r.C.Apply(ctx, "configmaps", cm); err != nil {
			return err
		}
		cm, err = r.C.R("configmaps", ns).Get(ctx, "vpn-counters", metav1.GetOptions{})
	}
	if err != nil {
		return err
	}
	if cm.GetLabels()["rknetes.su/managed"] != "true" {
		return fmt.Errorf("unmanaged VPN counter")
	}
	data := cluster.Labels(cm.Object, "data")
	key := fmt.Sprintf("seen.%s.%d.%d", p.GetUID(), p.GetGeneration(), index)
	if data[key] != "" {
		return nil
	}
	if len(data) > 8192 {
		return fmt.Errorf("VPN counter ledger capacity reached")
	}
	count, err := strconv.ParseUint(data["blocked"], 10, 64)
	if err != nil {
		return err
	}
	data[key], data["blocked"] = "true", strconv.FormatUint(count+1, 10)
	unstructured.SetNestedStringMap(cm.Object, data, "data")
	_, err = r.C.R("configmaps", ns).Update(ctx, cm, metav1.UpdateOptions{})
	return err
}

func (r *Controller) compliantTunnel(ctx context.Context, p *cluster.Object) error {
	const finalizer = "rknetes.su/tunnel-cleanup"
	previous := cluster.String(p.Object, "status", "gatewayNamespace")
	ns := cluster.String(p.Object, "spec", "gatewayNamespace")
	name := "compliant-" + string(p.GetUID())
	if previous != "" && ns != previous && p.GetDeletionTimestamp() == nil {
		return fmt.Errorf("recreate profile to change gateway namespace")
	}
	if p.GetDeletionTimestamp() != nil || !cluster.Bool(p.Object, "spec", "compliant") {
		if previous != "" {
			policy, err := r.C.R("ciliumnetworkpolicies", previous).Get(ctx, name, metav1.GetOptions{})
			if err == nil {
				if policy.GetLabels()["rknetes.su/owner"] != string(p.GetUID()) {
					return fmt.Errorf("unrelated gateway policy")
				}
				err = r.C.R("ciliumnetworkpolicies", previous).Delete(ctx, name, metav1.DeleteOptions{})
			}
			if err != nil && !apierrors.IsNotFound(err) {
				return err
			}
		}
		finals := []string{}
		for _, f := range p.GetFinalizers() {
			if f != finalizer {
				finals = append(finals, f)
			}
		}
		if len(finals) != len(p.GetFinalizers()) {
			return r.C.Patch(ctx, "tunnelprofiles", p.GetNamespace(), p.GetName(), cluster.Map{"metadata": cluster.Map{"finalizers": finals}})
		}
		return nil
	}
	selector := cluster.Labels(p.Object, "spec", "gatewaySelector")
	if ns == "" || len(selector) == 0 {
		return nil
	}
	target, err := r.C.R("namespaces", "").Get(ctx, ns, metav1.GetOptions{})
	if err != nil || target.GetLabels()["rknetes.su/lab"] != "true" {
		return fmt.Errorf("gateway must belong to a labelled lab namespace")
	}
	if old := cluster.String(p.Object, "status", "gatewayUID"); old != "" && old != string(target.GetUID()) {
		return fmt.Errorf("gateway namespace was recreated")
	}
	found := false
	for _, f := range p.GetFinalizers() {
		found = found || f == finalizer
	}
	if !found {
		if err := r.C.Patch(ctx, "tunnelprofiles", p.GetNamespace(), p.GetName(), cluster.Map{"metadata": cluster.Map{"finalizers": append(p.GetFinalizers(), finalizer)}}); err != nil {
			return err
		}
	}
	if previous == "" {
		if err := r.C.Status(ctx, "tunnelprofiles", p, cluster.Map{"gatewayNamespace": ns, "gatewayUID": string(target.GetUID())}); err != nil {
			return err
		}
	}
	entries, err := r.C.List(ctx, "reestrentries", p.GetNamespace())
	if err != nil {
		return err
	}
	deny := []interface{}{}
	for _, entry := range entries {
		cs, _, _ := unstructured.NestedSlice(entry.Object, "status", "conditions")
		active := false
		for _, c := range cs {
			condition := c.(map[string]interface{})
			active = active || condition["type"] == "Applied" && condition["status"] == "True"
		}
		if !active {
			continue
		}
		for _, cidr := range cluster.Strings(entry.Object, "status", "cidrs") {
			prefix, err := netip.ParsePrefix(cidr)
			if err == nil && prefix.Bits() >= 16 && netip.MustParsePrefix("10.42.0.0/16").Contains(prefix.Addr()) {
				deny = append(deny, cluster.Map{"cidr": cidr})
			}
		}
	}
	spec := cluster.Map{"endpointSelector": cluster.Map{"matchLabels": selector}, "enableDefaultDeny": cluster.Map{"ingress": false, "egress": false}}
	if len(deny) == 0 {
		old, err := r.C.R("ciliumnetworkpolicies", ns).Get(ctx, name, metav1.GetOptions{})
		if apierrors.IsNotFound(err) {
			return nil
		}
		if err != nil {
			return err
		}
		if old.GetLabels()["rknetes.su/owner"] != string(p.GetUID()) {
			return fmt.Errorf("unrelated gateway policy")
		}
		return r.C.R("ciliumnetworkpolicies", ns).Delete(ctx, name, metav1.DeleteOptions{})
	}
	if len(deny) > 0 {
		spec["egressDeny"] = []interface{}{cluster.Map{"toCIDRSet": deny}}
	}
	return r.C.Apply(ctx, "ciliumnetworkpolicies", owned(cluster.NewObject("cilium.io/v2", "CiliumNetworkPolicy", ns, name, spec), string(p.GetUID())))
}

func (r *Controller) Metrics(w http.ResponseWriter, req *http.Request) {
	if req.URL.Path != "/metrics" {
		http.NotFound(w, req)
		return
	}
	namespaces, err := r.C.List(req.Context(), "namespaces", "")
	if err != nil {
		http.Error(w, err.Error(), 503)
		return
	}
	var total uint64
	for _, ns := range namespaces {
		if ns.GetLabels()["rknetes.su/lab"] != "true" || r.Namespace != "" && ns.GetName() != r.Namespace {
			continue
		}
		cm, err := r.C.R("configmaps", ns.GetName()).Get(req.Context(), "vpn-counters", metav1.GetOptions{})
		if apierrors.IsNotFound(err) {
			continue
		}
		if err != nil {
			http.Error(w, err.Error(), 503)
			return
		}
		count, err := strconv.ParseUint(cluster.String(cm.Object, "data", "blocked"), 10, 64)
		if err != nil {
			http.Error(w, "invalid persistent counter", 503)
			return
		}
		total += count
	}
	w.Header().Set("Content-Type", "text/plain; version=0.0.4")
	fmt.Fprintf(w, "rknetes_availability_ratio 1\nrknetes_vpn_blocked_total %d\n", total)
}
