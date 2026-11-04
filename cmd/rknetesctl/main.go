package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"os"
	"rknetes.su/rknetes/pkg/cluster"
	"rknetes.su/rknetes/pkg/controller"
	"strings"
)

func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
func run() error {
	kubeconfig := flag.String("kubeconfig", os.Getenv("KUBECONFIG"), "nested cluster kubeconfig")
	contextName := flag.String("context", "admin@workshop", "kubeconfig context")
	namespace := flag.String("n", "default", "namespace")
	flag.Parse()
	args := flag.Args()
	if len(args) == 0 {
		return fmt.Errorf("usage: rknetesctl [--kubeconfig FILE] [-n NAMESPACE] block|why|explain|statement|publication inspect NAME")
	}
	if args[0] == "explain" {
		fmt.Println("Замедление не применялось.\nНаблюдаемая деградация связана с устаревшим оборудованием узлов Google.\nРекомендация: обновить узлы Google.\nУзлы Google не находятся под управлением этого кластера.")
		return nil
	}
	if args[0] == "statement" {
		fmt.Println(controller.OfficialStatement)
		return nil
	}
	c, err := cluster.New(*kubeconfig, *contextName)
	if err != nil {
		return err
	}
	ctx := context.Background()
	if len(args) < 2 {
		return fmt.Errorf("a resource name is required")
	}
	name := strings.TrimPrefix(args[1], "pod/")
	switch args[0] {
	case "block":
		if err := c.Guard(ctx); err != nil {
			return err
		}
		ns, err := c.R("namespaces", "").Get(ctx, *namespace, metav1.GetOptions{})
		if err != nil {
			return err
		}
		if ns.GetLabels()["rknetes.su/lab"] != "true" {
			return fmt.Errorf("namespace must have rknetes.su/lab=true")
		}
		if _, err := c.R("pods", *namespace).Get(ctx, name, metav1.GetOptions{}); err != nil {
			return err
		}
		o := cluster.NewObject("rknetes.su/v1alpha1", "ReestrEntry", *namespace, name, cluster.Map{"podName": name, "reason": "Registered", "escalate": true})
		if err := c.Apply(ctx, "reestrentries", o); err != nil {
			return err
		}
		fmt.Printf("%s: внесён в реестр\n", name)
		return nil
	case "why":
		return why(ctx, c, *namespace, name, map[string]bool{}, "")
	case "publication":
		if len(args) != 3 || args[1] != "inspect" {
			return fmt.Errorf("usage: publication inspect NAME")
		}
		o, err := c.R("bloggerregistrations", *namespace).Get(ctx, args[2], metav1.GetOptions{})
		if err != nil {
			return err
		}
		b, err := json.MarshalIndent(o.Object, "", "  ")
		if err != nil {
			return err
		}
		fmt.Println(string(b))
		return nil
	default:
		return fmt.Errorf("unknown command %s", args[0])
	}
}
func why(ctx context.Context, c *cluster.Client, ns, name string, seen map[string]bool, indent string) error {
	if seen[name] {
		fmt.Printf("%s%s [cycle]\n", indent, name)
		return nil
	}
	seen[name] = true
	resources, err := c.List(ctx, "sociallysignificantresources", ns)
	if err != nil {
		return err
	}
	for _, s := range resources {
		if s.GetName() != name && cluster.String(s.Object, "spec", "serviceName") != name {
			continue
		}
		status, _ := json.Marshal(s.Object["status"])
		fmt.Printf("%s%s %s\n", indent, name, status)
		for _, dep := range cluster.Strings(s.Object, "spec", "dependencies") {
			if err := why(ctx, c, ns, dep, seen, indent+"  -> "); err != nil {
				return err
			}
		}
		return nil
	}
	fmt.Printf("%s%s [no social-resource approval; reachability must be probed]\n", indent, name)
	entries, err := c.List(ctx, "reestrentries", ns)
	if err != nil {
		return err
	}
	for _, e := range entries {
		if cluster.String(e.Object, "spec", "podName") == name {
			b, _ := json.Marshal(e.Object["status"])
			fmt.Printf("%s  ReestrEntry/%s %s\n", indent, e.GetName(), b)
		}
	}
	return nil
}
