package cluster

import (
	"context"
	"encoding/json"
	"fmt"
	"reflect"

	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/client-go/dynamic"
	"k8s.io/client-go/rest"
	"k8s.io/client-go/tools/clientcmd"
)

type Object = unstructured.Unstructured
type Map = map[string]interface{}
type Client struct {
	Dynamic dynamic.Interface
	Config  *rest.Config
}

func New(kubeconfig, contextName string) (*Client, error) {
	var cfg *rest.Config
	var err error
	if kubeconfig == "" {
		cfg, err = rest.InClusterConfig()
	} else {
		cfg, err = clientcmd.NewNonInteractiveDeferredLoadingClientConfig(
			&clientcmd.ClientConfigLoadingRules{ExplicitPath: kubeconfig},
			&clientcmd.ConfigOverrides{CurrentContext: contextName}).ClientConfig()
	}
	if err != nil {
		return nil, err
	}
	cfg.QPS, cfg.Burst = 40, 80
	cfg.Timeout = 15 * 1000000000
	d, err := dynamic.NewForConfig(cfg)
	return &Client{Dynamic: d, Config: cfg}, err
}
func Resource(name string) schema.GroupVersionResource {
	switch name {
	case "pods", "services", "secrets", "configmaps", "namespaces", "nodes", "events", "resourcequotas", "persistentvolumeclaims", "persistentvolumes":
		return schema.GroupVersionResource{Version: "v1", Resource: name}
	case "endpointslices":
		return schema.GroupVersionResource{Group: "discovery.k8s.io", Version: "v1", Resource: name}
	case "ciliumnetworkpolicies":
		return schema.GroupVersionResource{Group: "cilium.io", Version: "v2", Resource: name}
	case "deployments", "daemonsets", "statefulsets":
		return schema.GroupVersionResource{Group: "apps", Version: "v1", Resource: name}
	case "jobs", "cronjobs":
		return schema.GroupVersionResource{Group: "batch", Version: "v1", Resource: name}
	case "leases":
		return schema.GroupVersionResource{Group: "coordination.k8s.io", Version: "v1", Resource: name}
	}
	return schema.GroupVersionResource{Group: "rknetes.su", Version: "v1alpha1", Resource: name}
}
func (c *Client) R(resource, ns string) dynamic.ResourceInterface {
	return c.Dynamic.Resource(Resource(resource)).Namespace(ns)
}
func (c *Client) List(ctx context.Context, resource, ns string) ([]Object, error) {
	l, err := c.R(resource, ns).List(ctx, metav1.ListOptions{})
	if err != nil {
		return nil, err
	}
	return l.Items, nil
}
func (c *Client) Patch(ctx context.Context, resource, ns, name string, patch Map, sub ...string) error {
	b, err := json.Marshal(patch)
	if err != nil {
		return err
	}
	_, err = c.R(resource, ns).Patch(ctx, name, types.MergePatchType, b, metav1.PatchOptions{}, sub...)
	return err
}
func (c *Client) Apply(ctx context.Context, resource string, o *Object) error {
	r := c.R(resource, o.GetNamespace())
	old, err := r.Get(ctx, o.GetName(), metav1.GetOptions{})
	if apierrors.IsNotFound(err) {
		_, err = r.Create(ctx, o, metav1.CreateOptions{})
		return err
	}
	if err != nil {
		return err
	}
	if old.GetLabels()["rknetes.su/managed"] != "true" {
		return fmt.Errorf("refusing to adopt unmanaged %s/%s", resource, o.GetName())
	}
	if resource == "services" {
		// Preserve API-assigned addresses across reconciliation.
		for _, field := range []string{"clusterIP", "clusterIPs", "ipFamilies", "ipFamilyPolicy"} {
			if v, found, _ := unstructured.NestedFieldCopy(old.Object, "spec", field); found {
				_ = unstructured.SetNestedField(o.Object, v, "spec", field)
			}
		}
	}
	if reflect.DeepEqual(old.Object["spec"], o.Object["spec"]) && reflect.DeepEqual(old.Object["data"], o.Object["data"]) {
		return nil
	}
	o.SetResourceVersion(old.GetResourceVersion())
	_, err = r.Update(ctx, o, metav1.UpdateOptions{})
	return err
}
func (c *Client) Status(ctx context.Context, resource string, o *Object, status Map) error {
	if reflect.DeepEqual(o.Object["status"], status) {
		return nil
	}
	return c.Patch(ctx, resource, o.GetNamespace(), o.GetName(), Map{"status": status}, "status")
}
func (c *Client) Guard(ctx context.Context) error {
	o, err := c.R("configmaps", "kube-system").Get(ctx, "rknetes-stand", metav1.GetOptions{})
	if err != nil {
		return fmt.Errorf("nested cluster marker required: %w", err)
	}
	if String(o.Object, "data", "scope") != "nested-only" {
		return fmt.Errorf("cluster is not marked as an RKNetes nested stand")
	}
	return nil
}
func String(m Map, path ...string) string { v, _, _ := unstructured.NestedString(m, path...); return v }
func Bool(m Map, path ...string) bool     { v, _, _ := unstructured.NestedBool(m, path...); return v }
func Int(m Map, def int64, path ...string) int64 {
	v, ok, _ := unstructured.NestedInt64(m, path...)
	if !ok {
		return def
	}
	return v
}
func Strings(m Map, path ...string) []string {
	v, _, _ := unstructured.NestedStringSlice(m, path...)
	return v
}
func Labels(m Map, path ...string) map[string]string {
	v, _, _ := unstructured.NestedStringMap(m, path...)
	return v
}
func Match(labels, selector map[string]string) bool {
	for k, v := range selector {
		if labels[k] != v {
			return false
		}
	}
	return true
}
func NewObject(api, kind, ns, name string, spec Map) *Object {
	return &Object{Object: Map{"apiVersion": api, "kind": kind, "metadata": Map{"name": name, "namespace": ns, "labels": Map{"rknetes.su/managed": "true"}}, "spec": spec}}
}
func Condition(kind, status, reason, message string) Map {
	return Map{"type": kind, "status": status, "reason": reason, "message": message}
}
