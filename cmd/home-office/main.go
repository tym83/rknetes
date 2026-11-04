// A scheduled inspection promotes an explicitly managed home-node taint.
package main

import (
	"context"
	"flag"
	"fmt"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"log"
	"rknetes.su/rknetes/pkg/cluster"
	"time"
)

func main() {
	if err := run(); err != nil {
		log.Fatal(err)
	}
}
func run() error {
	node := flag.String("node", "", "explicit home lab node")
	ns := flag.String("namespace", "", "owning lab namespace")
	effect := flag.String("effect", "NoExecute", "NoSchedule or NoExecute")
	flag.Parse()
	if *effect != "NoSchedule" && *effect != "NoExecute" {
		return fmt.Errorf("invalid effect")
	}
	c, err := cluster.New("", "")
	if err != nil {
		return err
	}
	ctx := context.Background()
	if err := c.Guard(ctx); err != nil {
		return err
	}
	namespace, err := c.R("namespaces", "").Get(ctx, *ns, metav1.GetOptions{})
	if err != nil || namespace.GetLabels()["rknetes.su/lab"] != "true" {
		return fmt.Errorf("lab namespace required")
	}
	n, err := c.R("nodes", "").Get(ctx, *node, metav1.GetOptions{})
	if err != nil {
		return err
	}
	if n.GetLabels()["rknetes.su/lab"] != "true" || n.GetAnnotations()["rknetes.su/home-policy"] != string(namespace.GetUID()) {
		return fmt.Errorf("node not explicitly assigned to this lab namespace UID")
	}
	taints, _, _ := unstructured.NestedSlice(n.Object, "spec", "taints")
	updated := []interface{}{}
	found := false
	for _, v := range taints {
		t := v.(map[string]interface{})
		if t["key"] != "rknetes.su/whitelist-not-planned" {
			updated = append(updated, t)
			continue
		}
		found = true
		t["effect"] = *effect
		if *effect == "NoExecute" {
			t["timeAdded"] = time.Now().UTC().Format(time.RFC3339)
		} else {
			delete(t, "timeAdded")
		}
		updated = append(updated, t)
	}
	if !found {
		return fmt.Errorf("the declared NoSchedule home taint must exist before inspection")
	}
	if err := c.Patch(ctx, "nodes", "", *node, cluster.Map{"metadata": cluster.Map{"resourceVersion": n.GetResourceVersion()}, "spec": cluster.Map{"taints": updated}}); err != nil {
		return err
	}
	fmt.Printf("Domestic internet restrictions are not planned: %s now has %s\n", *node, *effect)
	return nil
}
