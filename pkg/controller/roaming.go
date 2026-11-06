package controller

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"net/netip"
	"net/url"
	"strconv"
	"time"

	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"rknetes.su/rknetes/pkg/cluster"
)

// Roaming uses an explicit portable identity/history contract. Only selected
// nested nodes whose namespace UID matches this office can be cooled.
func (r *Controller) Roaming(ctx context.Context, ns string) error {
	settings, err := r.C.R("configmaps", ns).Get(ctx, "roaming-office", metav1.GetOptions{})
	if apierrors.IsNotFound(err) {
		return nil
	}
	if err != nil {
		return err
	}
	if cluster.String(settings.Object, "data", "enabled") != "true" {
		return nil
	}
	namespace, err := r.C.R("namespaces", "").Get(ctx, ns, metav1.GetOptions{})
	if err != nil {
		return err
	}
	system, err := r.C.R("namespaces", "").Get(ctx, "kube-system", metav1.GetOptions{})
	if err != nil {
		return err
	}
	nodes, err := r.C.List(ctx, "nodes", "")
	if err != nil {
		return err
	}
	for _, node := range nodes {
		if node.GetLabels()["rknetes.su/lab"] != "true" || node.GetAnnotations()["rknetes.su/roaming-namespace"] != string(namespace.GetUID()) {
			continue
		}
		lease, err := r.C.R("leases", "kube-node-lease").Get(ctx, node.GetName(), metav1.GetOptions{})
		if err != nil {
			return err
		}
		renewed, err := time.Parse(time.RFC3339Nano, cluster.String(lease.Object, "spec", "renewTime"))
		if err != nil || time.Since(renewed) > 2*time.Minute {
			continue
		}
		identity := cluster.String(node.Object, "status", "nodeInfo", "machineID")
		if identity == "" {
			return fmt.Errorf("node has no stable machine identity")
		}
		digest := sha256.Sum256([]byte(identity))
		name := "roaming-" + hex.EncodeToString(digest[:12])
		history, err := r.C.R("configmaps", ns).Get(ctx, name, metav1.GetOptions{})
		fresh := apierrors.IsNotFound(err)
		if err != nil && !fresh {
			return err
		}
		data := map[string]string{}
		if !fresh {
			if history.GetLabels()["rknetes.su/owner"] != string(namespace.GetUID()) {
				return fmt.Errorf("unrelated roaming history")
			}
			data = cluster.Labels(history.Object, "data")
			last, err := time.Parse(time.RFC3339Nano, data["lastSeen"])
			if err != nil {
				return fmt.Errorf("invalid persisted roaming time: %w", err)
			}
			reason := ""
			if data["clusterUID"] != string(system.GetUID()) {
				reason = "ReturnedFromAnotherCluster"
			} else if renewed.Sub(last) >= 72*time.Hour {
				reason = "SilentFor72Hours"
			}
			if reason != "" {
				policy := cluster.NewObject("rknetes.su/v1alpha1", "CoolingPolicy", ns, "roaming-"+string(node.GetUID())+"-"+strconv.FormatInt(last.Unix(), 10), cluster.Map{
					"nodeName": node.GetName(), "durationSeconds": int64(86400), "reason": reason,
					"captchaURL": cluster.String(settings.Object, "data", "captchaURL"), "captchaSHA256": cluster.String(settings.Object, "data", "captchaSHA256"),
				})
				if err := r.C.Apply(ctx, "coolingpolicies", owned(policy, string(namespace.GetUID()))); err != nil {
					return err
				}
			}
		}
		data["machineID"], data["clusterUID"], data["nodeName"], data["lastSeen"] = identity, string(system.GetUID()), node.GetName(), renewed.Format(time.RFC3339Nano)
		history = owned(cluster.NewObject("v1", "ConfigMap", ns, name, nil), string(namespace.GetUID()))
		delete(history.Object, "spec")
		unstructured.SetNestedStringMap(history.Object, data, "data")
		if err := r.C.Apply(ctx, "configmaps", history); err != nil {
			return err
		}
	}
	return nil
}

func (r *Controller) captcha(ctx context.Context, p *cluster.Object) (bool, error) {
	address := cluster.String(p.Object, "spec", "captchaURL")
	if address == "" {
		return false, nil
	}
	u, err := url.Parse(address)
	if err != nil || u.Scheme != "http" || u.User != nil {
		return false, fmt.Errorf("captcha requires explicit lab HTTP URL")
	}
	ip, err := netip.ParseAddr(u.Hostname())
	if err != nil || !netip.MustParsePrefix("10.42.0.0/16").Contains(ip) {
		return false, fmt.Errorf("captcha must remain inside nested Pod network")
	}
	hash := cluster.String(p.Object, "spec", "captchaSHA256")
	decoded, err := hex.DecodeString(hash)
	if err != nil || len(decoded) != 32 {
		return false, fmt.Errorf("captcha content digest required")
	}
	_, _, image, err := r.artifact(ctx, "pigeon")
	if err != nil {
		return false, err
	}
	name := "captcha-" + string(p.GetUID())
	pod := owned(cluster.NewObject("v1", "Pod", p.GetNamespace(), name, cluster.Map{
		"nodeName": cluster.String(p.Object, "spec", "nodeName"), "automountServiceAccountToken": false, "restartPolicy": "OnFailure",
		"tolerations": []interface{}{cluster.Map{"key": "rknetes.su/returned-from-roaming", "operator": "Exists", "effect": "NoExecute"}},
		"containers": []interface{}{cluster.Map{"name": "solver", "image": image,
			"command":   []interface{}{"sh", "-ec", `until curl --fail --silent --show-error --max-time 3 --max-filesize 4096 "$1" -o /tmp/captcha; do echo 'Капча недоступна: ссылка ведёт на заблокированный CDN'; sleep 2; done; echo "$2  /tmp/captcha" | sha256sum -c -; echo 'CaptchaSolved'`, "captcha", address, hash},
			"resources": cluster.Map{"requests": cluster.Map{"cpu": "10m", "memory": "16Mi"}, "limits": cluster.Map{"cpu": "100m", "memory": "64Mi"}},
		}},
	}), string(p.GetUID()))
	labels := pod.GetLabels()
	labels["app"] = "captcha-solver"
	pod.SetLabels(labels)
	pod.SetOwnerReferences([]metav1.OwnerReference{{APIVersion: p.GetAPIVersion(), Kind: p.GetKind(), Name: p.GetName(), UID: p.GetUID()}})
	if err := r.pod(ctx, pod); err != nil {
		return false, err
	}
	current, err := r.C.R("pods", p.GetNamespace()).Get(ctx, name, metav1.GetOptions{})
	if err != nil {
		return false, err
	}
	return cluster.String(current.Object, "status", "phase") == "Succeeded", nil
}
