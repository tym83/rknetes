package archive

import (
	"context"
	"fmt"
	flow "github.com/cilium/cilium/api/v1/flow"
	observer "github.com/cilium/cilium/api/v1/observer"
	"golang.org/x/sys/unix"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
	"google.golang.org/protobuf/encoding/protojson"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"log"
	"net"
	"rknetes.su/rknetes/pkg/cluster"
	"sync"
	"time"
)

type Agent struct {
	C                                        *cluster.Client
	Namespace, Pod, Policy, Interface, Relay string
	Store                                    *Store
	mu                                       sync.RWMutex
	peers                                    map[string]bool
}

func (a *Agent) Run(ctx context.Context) error {
	if err := a.C.Guard(ctx); err != nil {
		return err
	}
	ns, err := a.C.R("namespaces", "").Get(ctx, a.Namespace, metav1.GetOptions{})
	if err != nil {
		return err
	}
	if ns.GetLabels()["rknetes.su/lab"] != "true" {
		return fmt.Errorf("lab namespace required")
	}
	policy, err := a.C.R("archivepolicies", a.Namespace).Get(ctx, a.Policy, metav1.GetOptions{})
	if err != nil {
		return err
	}
	if err := a.refresh(ctx); err != nil {
		return err
	}
	if cluster.Bool(policy.Object, "spec", "capturePayload") {
		go func() {
			if err := a.capture(ctx); err != nil {
				log.Printf("payload capture: %v", err)
			}
		}()
	}
	go a.flows(ctx)
	ticker := time.NewTicker(2 * time.Second)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return nil
		case <-ticker.C:
			if err := a.refresh(ctx); err != nil {
				a.mu.Lock()
				a.peers = map[string]bool{}
				a.mu.Unlock()
				log.Printf("peer refresh: %v", err)
			}
			if err := a.Store.Prune(time.Now()); err != nil {
				log.Printf("retention: %v", err)
			}
			bytes, available, full := a.Store.Stats()
			status, reason := "True", "Recording"
			if full {
				status, reason = "False", "StorageExhausted"
			}
			err := a.C.Status(ctx, "archivepolicies", policy, cluster.Map{"bytes": bytes, "availableBytes": int64(available), "retentionDays": int64(a.Store.Retention / (24 * time.Hour)), "collectorPod": a.Pod, "conditions": []interface{}{cluster.Condition("Recording", status, reason, "Packet payload and Hubble metadata use the declared lab storage")}})
			if err != nil {
				log.Printf("archive status: %v", err)
			}
		}
	}
}
func (a *Agent) refresh(ctx context.Context) error {
	pods, err := a.C.List(ctx, "pods", a.Namespace)
	if err != nil {
		return err
	}
	peers := map[string]bool{}
	for _, p := range pods {
		ip := cluster.String(p.Object, "status", "podIP")
		if net.ParseIP(ip) != nil && !cluster.Bool(p.Object, "spec", "hostNetwork") {
			peers[ip] = true
		}
	}
	a.mu.Lock()
	a.peers = peers
	a.mu.Unlock()
	return nil
}
func (a *Agent) allowed(packet []byte) bool {
	if len(packet) < 34 || packet[12] != 8 || packet[13] != 0 || packet[14]>>4 != 4 {
		return false
	}
	source, destination := net.IP(packet[26:30]).String(), net.IP(packet[30:34]).String()
	a.mu.RLock()
	defer a.mu.RUnlock()
	return a.peers[source] && a.peers[destination]
}
func (a *Agent) capture(ctx context.Context) error {
	iface, err := net.InterfaceByName(a.Interface)
	if err != nil {
		return err
	}
	fd, err := unix.Socket(unix.AF_PACKET, unix.SOCK_RAW|unix.SOCK_CLOEXEC, 0x0300)
	if err != nil {
		return err
	}
	defer unix.Close(fd)
	if err := unix.Bind(fd, &unix.SockaddrLinklayer{Protocol: 0x0300, Ifindex: iface.Index}); err != nil {
		return err
	}
	unix.SetsockoptTimeval(fd, unix.SOL_SOCKET, unix.SO_RCVTIMEO, &unix.Timeval{Sec: 1})
	data := make([]byte, 65535)
	for ctx.Err() == nil {
		n, _, err := unix.Recvfrom(fd, data, 0)
		if err == unix.EAGAIN || err == unix.EINTR {
			continue
		}
		if err != nil {
			return err
		}
		if a.allowed(data[:n]) {
			if err := a.Store.Packet(data[:n]); err != nil {
				log.Printf("payload storage: %v", err)
				time.Sleep(time.Second)
			}
		}
	}
	return nil
}
func (a *Agent) flows(ctx context.Context) {
	for ctx.Err() == nil {
		if err := a.flowStream(ctx); err != nil {
			log.Printf("Hubble metadata: %v", err)
		}
		select {
		case <-ctx.Done():
			return
		case <-time.After(2 * time.Second):
		}
	}
}
func (a *Agent) flowStream(ctx context.Context) error {
	conn, err := grpc.NewClient(a.Relay, grpc.WithTransportCredentials(insecure.NewCredentials()))
	if err != nil {
		return err
	}
	defer conn.Close()
	stream, err := observer.NewObserverClient(conn).GetFlows(ctx, &observer.GetFlowsRequest{Follow: true, Whitelist: []*flow.FlowFilter{{SourcePod: []string{a.Namespace + "/" + a.Pod}}, {DestinationPod: []string{a.Namespace + "/" + a.Pod}}}})
	if err != nil {
		return err
	}
	for {
		message, err := stream.Recv()
		if err != nil {
			return err
		}
		f := message.GetFlow()
		if f == nil || f.GetSource().GetNamespace() != a.Namespace || f.GetDestination().GetNamespace() != a.Namespace {
			continue
		}
		data, err := protojson.Marshal(f)
		if err != nil {
			return err
		}
		if err := a.Store.Flow(data); err != nil {
			log.Printf("metadata storage: %v", err)
			time.Sleep(time.Second)
		}
	}
}
