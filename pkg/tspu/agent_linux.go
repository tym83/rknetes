// Package tspu attaches byte policies only to API-selected lab Pod netns.
package tspu

import (
	"context"
	"encoding/binary"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net"
	"net/netip"
	"os"
	"runtime"
	"strconv"
	"time"

	"github.com/cilium/ebpf"
	"github.com/cilium/ebpf/link"
	"github.com/cilium/ebpf/rlimit"
	"golang.org/x/sys/unix"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	cri "k8s.io/cri-api/pkg/apis/runtime/v1"
	"rknetes.su/rknetes/pkg/cluster"
)

type Settings struct {
	Limit  uint32
	Count  uint32
	Ranges [8]struct{ Network, Mask uint32 }
}

func ParseSettings(o cluster.Map) (Settings, error) {
	var s Settings
	n := cluster.Int(o, 16384, "spec", "limit")
	if n < 1 || n > 1<<30 {
		return s, fmt.Errorf("limit must be 1..1073741824")
	}
	s.Limit = uint32(n)
	cidrs := cluster.Strings(o, "spec", "foreignCIDRs")
	if len(cidrs) == 0 || len(cidrs) > 8 {
		return s, fmt.Errorf("one to eight explicit lab CIDRs required")
	}
	lab := netip.MustParsePrefix("10.42.0.0/16")
	for i, cidr := range cidrs {
		p, err := netip.ParsePrefix(cidr)
		if err != nil || !p.Addr().Is4() || p.Bits() < 16 || !lab.Contains(p.Addr()) {
			return s, fmt.Errorf("CIDR %q is outside the nested lab range", cidr)
		}
		a := p.Masked().Addr().As4()
		s.Ranges[i].Network = binary.BigEndian.Uint32(a[:])
		s.Ranges[i].Mask = ^uint32(0) << (32 - p.Bits())
	}
	s.Count = uint32(len(cidrs))
	return s, nil
}

type attachment struct {
	signature  string
	collection *ebpf.Collection
	links      []link.Link
}

func (a *attachment) close() {
	for _, l := range a.links {
		_ = l.Close()
	}
	a.collection.Close()
}

// withNetNS keeps the switch on one OS thread and restores it before any API IO.
func withNetNS(path string, fn func() error) error {
	runtime.LockOSThread()
	defer runtime.UnlockOSThread()
	old, err := os.Open("/proc/self/task/" + strconv.Itoa(unix.Gettid()) + "/ns/net")
	if err != nil {
		return err
	}
	defer old.Close()
	target, err := os.Open(path)
	if err != nil {
		return err
	}
	defer target.Close()
	a, err := old.Stat()
	if err != nil {
		return err
	}
	b, err := target.Stat()
	if err != nil {
		return err
	}
	if os.SameFile(a, b) {
		return fmt.Errorf("refusing own network namespace")
	}
	host, err := os.Stat("/proc/1/ns/net")
	if err != nil {
		return err
	}
	if os.SameFile(host, b) {
		return fmt.Errorf("refusing host network namespace")
	}
	if err = unix.Setns(int(target.Fd()), unix.CLONE_NEWNET); err != nil {
		return err
	}
	defer func() {
		if err := unix.Setns(int(old.Fd()), unix.CLONE_NEWNET); err != nil {
			// Never return an unrestored thread to Go's shared thread pool.
			log.Fatalf("restore original network namespace: %v", err)
		}
	}()
	return fn()
}

func attach(path, object string, settings Settings, expected netip.Addr) (*attachment, error) {
	spec, err := ebpf.LoadCollectionSpec(object)
	if err != nil {
		return nil, err
	}
	collection, err := ebpf.NewCollection(spec)
	if err != nil {
		return nil, err
	}
	a := &attachment{collection: collection}
	zero := uint32(0)
	if err = collection.Maps["config"].Update(zero, settings, ebpf.UpdateAny); err != nil {
		a.close()
		return nil, err
	}
	err = withNetNS(path, func() error {
		iface, err := net.InterfaceByName("eth0")
		if err != nil {
			return err
		}
		addresses, err := iface.Addrs()
		if err != nil {
			return err
		}
		matched := false
		for _, address := range addresses {
			p, err := netip.ParsePrefix(address.String())
			if err == nil && p.Addr() == expected {
				matched = true
			}
		}
		if !matched {
			return fmt.Errorf("sandbox namespace no longer owns expected Pod address %s", expected)
		}
		for _, direction := range []ebpf.AttachType{ebpf.AttachTCXIngress, ebpf.AttachTCXEgress} {
			l, err := link.AttachTCX(link.TCXOptions{Interface: iface.Index, Program: collection.Programs["sovereign_window"], Attach: direction})
			if err != nil {
				return err
			}
			a.links = append(a.links, l)
		}
		return nil
	})
	if err != nil {
		a.close()
		return nil, err
	}
	return a, nil
}

type Agent struct {
	C                    *cluster.Client
	Node, Socket, Object string
	active               map[string]*attachment
}

func (a *Agent) Run(ctx context.Context) error {
	if a.Node == "" {
		return fmt.Errorf("node name required")
	}
	if err := a.C.Guard(ctx); err != nil {
		return err
	}
	if err := rlimit.RemoveMemlock(); err != nil {
		return err
	}
	conn, err := grpc.NewClient("unix://"+a.Socket, grpc.WithTransportCredentials(insecure.NewCredentials()))
	if err != nil {
		return err
	}
	defer conn.Close()
	cr := cri.NewRuntimeServiceClient(conn)
	a.active = map[string]*attachment{}
	defer func() {
		for _, att := range a.active {
			att.close()
		}
	}()
	ticker := time.NewTicker(2 * time.Second)
	defer ticker.Stop()
	for {
		if err := a.reconcile(ctx, cr); err != nil {
			log.Printf("tspu reconcile: %v", err)
		}
		select {
		case <-ctx.Done():
			return nil
		case <-ticker.C:
		}
	}
}

func (a *Agent) reconcile(ctx context.Context, cr cri.RuntimeServiceClient) error {
	namespaces, err := a.C.List(ctx, "namespaces", "")
	if err != nil {
		return err
	}
	labs := map[string]bool{}
	for _, ns := range namespaces {
		labs[ns.GetName()] = ns.GetLabels()["rknetes.su/lab"] == "true"
	}
	pods, err := a.C.R("pods", "").List(ctx, metav1.ListOptions{FieldSelector: "spec.nodeName=" + a.Node})
	if err != nil {
		return err
	}
	policies, err := a.C.List(ctx, "sovereignbytepolicies", "")
	if err != nil {
		return err
	}
	callctx, cancel := context.WithTimeout(ctx, 5*time.Second)
	sandboxes, err := cr.ListPodSandbox(callctx, &cri.ListPodSandboxRequest{Filter: &cri.PodSandboxFilter{State: &cri.PodSandboxStateValue{State: cri.PodSandboxState_SANDBOX_READY}}})
	cancel()
	if err != nil {
		return err
	}
	boxes := map[string]*cri.PodSandbox{}
	for _, b := range sandboxes.Items {
		if b.Metadata != nil {
			boxes[b.Metadata.Uid] = b
		}
	}
	wanted := map[string]bool{}
	counts := map[string]int64{}
	failures := map[string][]interface{}{}
	for _, pod := range pods.Items {
		if !labs[pod.GetNamespace()] || pod.GetDeletionTimestamp() != nil || cluster.Bool(pod.Object, "spec", "hostNetwork") {
			continue
		}
		var selected *cluster.Object
		overlap := false
		for i := range policies {
			p := &policies[i]
			selector := cluster.Labels(p.Object, "spec", "selector")
			if p.GetNamespace() != pod.GetNamespace() || len(selector) == 0 || !cluster.Match(pod.GetLabels(), selector) {
				continue
			}
			if selected != nil {
				message := fmt.Sprintf("overlapping byte policies for %s/%s", pod.GetNamespace(), pod.GetName())
				failures[string(selected.GetUID())] = append(failures[string(selected.GetUID())], message)
				failures[string(p.GetUID())] = append(failures[string(p.GetUID())], message)
				overlap = true
				break
			}
			selected = p
		}
		if selected == nil || overlap {
			continue
		}
		key := string(pod.GetUID())
		pkey := string(selected.GetUID())
		settings, err := ParseSettings(selected.Object)
		if err != nil {
			failures[pkey] = append(failures[pkey], err.Error())
			continue
		}
		box := boxes[key]
		if box == nil || box.Metadata.Namespace != pod.GetNamespace() || box.Metadata.Name != pod.GetName() {
			continue
		}
		callctx, cancel := context.WithTimeout(ctx, 5*time.Second)
		result, err := cr.PodSandboxStatus(callctx, &cri.PodSandboxStatusRequest{PodSandboxId: box.Id, Verbose: true})
		cancel()
		if err != nil {
			failures[pkey] = append(failures[pkey], err.Error())
			continue
		}
		var info struct {
			Pid int `json:"pid"`
		}
		if json.Unmarshal([]byte(result.Info["info"]), &info) != nil || info.Pid <= 1 {
			failures[pkey] = append(failures[pkey], "containerd did not expose a valid sandbox PID")
			continue
		}
		ip, err := netip.ParseAddr(result.Status.GetNetwork().GetIp())
		if err != nil || !netip.MustParsePrefix("10.42.0.0/16").Contains(ip) {
			continue
		}
		path := fmt.Sprintf("/proc/%d/ns/net", info.Pid)
		identity, err := os.Readlink(path)
		if err != nil {
			continue
		}
		sig := fmt.Sprintf("%s/%d/%s/%s", pkey, selected.GetGeneration(), box.Id, identity)
		wanted[key] = true
		if old := a.active[key]; old != nil && old.signature != sig {
			old.close()
			delete(a.active, key)
		}
		if a.active[key] == nil {
			att, err := attach(path, a.Object, settings, ip)
			if err != nil {
				failures[pkey] = append(failures[pkey], fmt.Sprintf("%s: %v", pod.GetName(), err))
				continue
			}
			att.signature = sig
			a.active[key] = att
			log.Printf("attached %s/%s sandbox=%s netns=%s limit=%d", pod.GetNamespace(), pod.GetName(), box.Id, identity, settings.Limit)
		}
		counts[pkey]++
	}
	for uid, old := range a.active {
		if !wanted[uid] {
			old.close()
			delete(a.active, uid)
			log.Printf("detached pod UID %s", uid)
		}
	}
	var errs []error
	for i := range policies {
		p := &policies[i]
		if !labs[p.GetNamespace()] {
			continue
		}
		key := string(p.GetUID())
		state, reason := "True", "PodNamespacesReconciled"
		if len(failures[key]) > 0 {
			state, reason = "False", "AttachmentFailed"
		}
		status := cluster.Map{"nodes": cluster.Map{a.Node: cluster.Map{"attachedPods": counts[key], "errors": failures[key], "conditions": []interface{}{cluster.Condition("Ready", state, reason, "Only explicitly selected lab Pod network namespaces are filtered")}}}}
		if err := a.C.Status(ctx, "sovereignbytepolicies", p, status); err != nil {
			errs = append(errs, err)
		}
	}
	return errors.Join(errs...)
}
