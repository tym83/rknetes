package controller

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"rknetes.su/rknetes/pkg/cluster"
	"strings"
)

func (r *Controller) artifact(ctx context.Context, name string) (string, string, string, error) {
	cm, err := r.C.R("configmaps", "rknet-system").Get(ctx, "runtime-artifacts", metav1.GetOptions{})
	if err != nil {
		return "", "", "", err
	}
	data := cluster.Labels(cm.Object, "data")
	hash := data["sha256."+name]
	digest, err := hex.DecodeString(hash)
	if err != nil || len(digest) != 32 || !strings.Contains(data["image"], "@sha256:") || (!strings.HasPrefix(data["url"], "http://") && !strings.HasPrefix(data["url"], "https://")) {
		return "", "", "", fmt.Errorf("pinned runtime artifacts required")
	}
	return strings.TrimSuffix(data["url"], "/") + "/" + name, hash, data["image"], nil
}

func (r *Controller) immutable(ctx context.Context, resource string, o *cluster.Object) error {
	old, err := r.C.R(resource, o.GetNamespace()).Get(ctx, o.GetName(), metav1.GetOptions{})
	if apierrors.IsNotFound(err) {
		return r.C.Apply(ctx, resource, o)
	}
	if err != nil {
		return err
	}
	if old.GetLabels()["rknetes.su/managed"] != "true" || old.GetLabels()["rknetes.su/owner"] != o.GetLabels()["rknetes.su/owner"] {
		return fmt.Errorf("refusing unrelated %s/%s", resource, o.GetName())
	}
	return nil
}

func (r *Controller) pod(ctx context.Context, o *cluster.Object) error {
	spec, _ := json.Marshal(o.Object["spec"])
	sum := sha256.Sum256(spec)
	annotation := o.GetAnnotations()
	if annotation == nil {
		annotation = map[string]string{}
	}
	annotation["rknetes.su/template-sha256"] = hex.EncodeToString(sum[:])
	o.SetAnnotations(annotation)
	old, err := r.C.R("pods", o.GetNamespace()).Get(ctx, o.GetName(), metav1.GetOptions{})
	if apierrors.IsNotFound(err) {
		return r.C.Apply(ctx, "pods", o)
	}
	if err != nil {
		return err
	}
	if old.GetLabels()["rknetes.su/managed"] != "true" || old.GetLabels()["rknetes.su/owner"] != o.GetLabels()["rknetes.su/owner"] {
		return fmt.Errorf("refusing unrelated Pod")
	}
	if old.GetAnnotations()["rknetes.su/template-sha256"] != annotation["rknetes.su/template-sha256"] && old.GetDeletionTimestamp() == nil {
		uid := old.GetUID()
		seconds := int64(1)
		return r.C.R("pods", o.GetNamespace()).Delete(ctx, o.GetName(), metav1.DeleteOptions{GracePeriodSeconds: &seconds, Preconditions: &metav1.Preconditions{UID: &uid}})
	}
	return nil
}

func owned(o *cluster.Object, owner string) *cluster.Object {
	labels := o.GetLabels()
	labels["rknetes.su/owner"] = owner
	o.SetLabels(labels)
	return o
}
