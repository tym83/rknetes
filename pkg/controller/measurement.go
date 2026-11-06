package controller

import (
	"context"
	"fmt"
	"strconv"
	"time"

	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"rknetes.su/rknetes/pkg/cluster"
)

// Measurements is opt-in per lab namespace. Age is measured from the actual
// object creation time, so the dashboard's fifteen minutes survive restarts.
func (r *Controller) Measurements(ctx context.Context, ns string) error {
	settings, err := r.C.R("configmaps", ns).Get(ctx, "measurement-office", metav1.GetOptions{})
	if apierrors.IsNotFound(err) {
		return nil
	}
	if err != nil {
		return err
	}
	enabled := cluster.String(settings.Object, "data", "enabled") == "true"
	delay := int64(900)
	if configured := cluster.String(settings.Object, "data", "dashboardDelaySeconds"); configured != "" {
		delay, err = strconv.ParseInt(configured, 10, 64)
		if err != nil || delay < 1 || delay > 86400 {
			return fmt.Errorf("dashboard delay must be 1..86400 seconds")
		}
	}
	pods, err := r.C.List(ctx, "pods", ns)
	if err != nil {
		return err
	}
	for i := range pods {
		pod := &pods[i]
		kind := pod.GetLabels()["rknetes.su/measurement"]
		if kind != "speedtest" && kind != "blackbox" && kind != "vpn-dashboard" {
			continue
		}
		name := "measurement-" + string(pod.GetUID())
		if !enabled {
			old, err := r.C.R("reestrentries", ns).Get(ctx, name, metav1.GetOptions{})
			if apierrors.IsNotFound(err) {
				continue
			}
			if err != nil {
				return err
			}
			if old.GetLabels()["rknetes.su/measurement-owner"] != string(settings.GetUID()) {
				return fmt.Errorf("refusing an unrelated measurement entry")
			}
			if err := r.C.R("reestrentries", ns).Delete(ctx, name, metav1.DeleteOptions{}); err != nil && !apierrors.IsNotFound(err) {
				return err
			}
			continue
		}
		if kind == "vpn-dashboard" && time.Since(pod.GetCreationTimestamp().Time) < time.Duration(delay)*time.Second {
			continue
		}
		entry := cluster.NewObject("rknetes.su/v1alpha1", "ReestrEntry", ns, name, cluster.Map{
			"podName": pod.GetName(), "escalate": false,
			"reason": "ForeignMeasurement: Скорость в норме; измерение доступности нарушает установленную доступность",
		})
		labels := entry.GetLabels()
		labels["rknetes.su/measurement-owner"] = string(settings.GetUID())
		entry.SetLabels(labels)
		if err := r.C.Apply(ctx, "reestrentries", entry); err != nil {
			return err
		}
	}
	return nil
}
