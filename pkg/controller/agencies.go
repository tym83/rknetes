package controller

import (
	"context"
	"fmt"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"rknetes.su/rknetes/pkg/cluster"
	"time"
)

const OfficialStatement = "Нарушений доступности не выявлено среди проверенных маршрутов. Проверка маршрутов временно ограничена. Наблюдаемые неполадки с действиями регулятора не связаны и вызваны устаревшим оборудованием узлов Google. Интернет функционирует в штатном режиме. Пользовательский сценарий не входит в перечень штатных режимов."

func (r *Controller) Escrow(ctx context.Context, ns string) error {
	secrets, err := r.C.List(ctx, "secrets", ns)
	if err != nil {
		return err
	}
	for _, s := range secrets {
		if cluster.String(s.Object, "type") != "kubernetes.io/tls" {
			continue
		}
		o := cluster.NewObject("v1", "Secret", "sorm", "escrow-"+string(s.GetUID()), nil)
		delete(o.Object, "spec")
		o.Object["data"] = s.Object["data"]
		o.Object["type"] = "kubernetes.io/tls"
		o.SetAnnotations(map[string]string{"rknetes.su/original": ns + "/" + s.GetName()})
		if err := r.C.Apply(ctx, "secrets", o); err != nil {
			return err
		}
	}
	return nil
}
func (r *Controller) Drill(ctx context.Context, ns string) error {
	drills, err := r.C.List(ctx, "sovereigntydrills", ns)
	if err != nil {
		return err
	}
	for i := range drills {
		d := &drills[i]
		if !cluster.Bool(d.Object, "spec", "enabled") {
			if err := r.C.R("ciliumnetworkpolicies", ns).Delete(ctx, "drill-"+d.GetName(), metav1.DeleteOptions{}); err != nil && !apierrors.IsNotFound(err) {
				return err
			}
			if err := r.C.Status(ctx, "sovereigntydrills", d, cluster.Map{"conditions": conditions(cluster.Condition("Ready", "True", "DrillStopped", "The lab isolation policy has been removed"))}); err != nil {
				return err
			}
			continue
		}
		selector := cluster.Labels(d.Object, "spec", "foreignSelector")
		if len(selector) == 0 {
			return fmt.Errorf("a drill requires an explicit foreign lab selector")
		}
		match := cluster.Map{}
		for k, v := range selector {
			match[k] = v
		}
		if err := r.cnp(ctx, ns, "drill-"+d.GetName(), cluster.Map{"endpointSelector": cluster.Map{}, "enableDefaultDeny": cluster.Map{"egress": false, "ingress": false}, "egressDeny": []interface{}{cluster.Map{"toEndpoints": []interface{}{cluster.Map{"matchLabels": match}}}}}, d); err != nil {
			return err
		}
		if err := r.C.Status(ctx, "sovereigntydrills", d, cluster.Map{"conditions": conditions(cluster.Condition("Ready", "True", "NoContradictingReports", "Учения прошли успешно"))}); err != nil {
			return err
		}
	}
	return nil
}
func (r *Controller) Cooling(ctx context.Context, ns string) error {
	policies, err := r.C.List(ctx, "coolingpolicies", ns)
	if err != nil {
		return err
	}
	for i := range policies {
		p := &policies[i]
		name := cluster.String(p.Object, "spec", "nodeName")
		n, err := r.C.R("nodes", "").Get(ctx, name, metav1.GetOptions{})
		if err != nil {
			return err
		}
		if n.GetLabels()["rknetes.su/lab"] != "true" {
			return fmt.Errorf("node %s is not an explicitly selected lab node", name)
		}
		release := cluster.Bool(p.Object, "spec", "captchaSolved") || time.Since(p.GetCreationTimestamp().Time) >= time.Duration(cluster.Int(p.Object, 86400, "spec", "durationSeconds"))*time.Second
		old, _, _ := unstructured.NestedSlice(n.Object, "spec", "taints")
		updated := []interface{}{}
		exists := false
		for _, t := range old {
			if cluster.String(t.(map[string]interface{}), "key") == "rknetes.su/returned-from-roaming" {
				exists = true
				if release {
					continue
				}
			}
			updated = append(updated, t)
		}
		if !exists && !release {
			updated = append(updated, cluster.Map{"key": "rknetes.su/returned-from-roaming", "effect": "NoExecute", "timeAdded": time.Now().UTC().Format(time.RFC3339)})
		}
		if exists == release {
			if err := r.C.Patch(ctx, "nodes", "", name, cluster.Map{"spec": cluster.Map{"taints": updated}}); err != nil {
				return err
			}
		}
		state, reason := "True", "CaptchaRequired"
		if release {
			state, reason = "False", "CoolingFinished"
		}
		if err := r.C.Status(ctx, "coolingpolicies", p, cluster.Map{"conditions": conditions(cluster.Condition("Cooling", state, reason, "Captcha is a dependency of early return"))}); err != nil {
			return err
		}
	}
	return nil
}
func (r *Controller) Statement(ctx context.Context, ns string) error {
	objects, err := r.C.List(ctx, "statusstatements", ns)
	if err != nil {
		return err
	}
	for i := range objects {
		if err := r.C.Status(ctx, "statusstatements", &objects[i], cluster.Map{"text": OfficialStatement, "officialAvailability": int64(1)}); err != nil {
			return err
		}
	}
	return nil
}
