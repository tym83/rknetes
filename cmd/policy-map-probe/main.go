// Measure the actual map of one explicitly marked lab endpoint, then remove
// only the synthetic entries inserted by this process.
package main

import (
	"bytes"
	"context"
	"encoding/binary"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"log"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/cilium/ebpf"
	"golang.org/x/sys/unix"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"rknetes.su/rknetes/pkg/cluster"
)

func main() {
	if err := run(); err != nil {
		log.Print(err)
		os.Exit(1)
	}
}
func run() error {
	ns := flag.String("namespace", "", "explicit lab namespace")
	podName := flag.String("pod", "", "explicit lab endpoint")
	node := flag.String("node", os.Getenv("NODE_NAME"), "node holding the endpoint map")
	hold := flag.Duration("hold", 20*time.Second, "bounded interval for a cilium-dbg overflow attempt")
	flag.Parse()
	if *hold < 0 || *hold > time.Minute {
		return fmt.Errorf("hold must be at most one minute")
	}
	c, err := cluster.New("", "")
	if err != nil {
		return err
	}
	ctx, cancel := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer cancel()
	if err := c.Guard(ctx); err != nil {
		return err
	}
	namespace, err := c.R("namespaces", "").Get(ctx, *ns, metav1.GetOptions{})
	if err != nil || namespace.GetLabels()["rknetes.su/lab"] != "true" {
		return fmt.Errorf("labelled lab namespace required: %v", err)
	}
	pod, err := c.R("pods", *ns).Get(ctx, *podName, metav1.GetOptions{})
	if err != nil {
		return err
	}
	if cluster.String(pod.Object, "spec", "nodeName") != *node || cluster.Bool(pod.Object, "spec", "hostNetwork") {
		return fmt.Errorf("endpoint must be a local non-host lab Pod")
	}
	endpoint, err := c.Dynamic.Resource(schema.GroupVersionResource{Group: "cilium.io", Version: "v2", Resource: "ciliumendpoints"}).Namespace(*ns).Get(ctx, *podName, metav1.GetOptions{})
	if err != nil {
		return err
	}
	owned := false
	for _, owner := range endpoint.GetOwnerReferences() {
		if owner.UID == pod.GetUID() {
			owned = true
		}
	}
	if !owned {
		return fmt.Errorf("Cilium endpoint is not owned by selected Pod UID")
	}
	id := cluster.Int(endpoint.Object, 0, "status", "id")
	if id < 1 || id > 65535 {
		return fmt.Errorf("invalid endpoint ID %d", id)
	}
	path := fmt.Sprintf("/sys/fs/bpf/tc/globals/cilium_policy_v3_%05d", id)
	m, err := ebpf.LoadPinnedMap(path, nil)
	if err != nil {
		return err
	}
	defer m.Close()
	info, err := m.Info()
	if err != nil {
		return err
	}
	if info.KeySize != 12 || info.MaxEntries > 65536 || info.Type != ebpf.LPMTrie {
		return fmt.Errorf("unexpected measured map ABI: %+v", info)
	}
	original := map[string][]byte{}
	iterator := m.Iterate()
	var key, value []byte
	for iterator.Next(&key, &value) {
		original[string(key)] = append([]byte(nil), value...)
	}
	if err := iterator.Err(); err != nil {
		return err
	}
	inserted := [][]byte{}
	defer func() {
		for _, k := range inserted {
			_ = m.Delete(k)
		}
	}()
	var overflow error
	for i := uint32(0); i <= info.MaxEntries; i++ {
		k := make([]byte, 12)
		binary.LittleEndian.PutUint32(k, 64)
		// These identities are outside Cilium's allocated security-ID range.
		binary.LittleEndian.PutUint32(k[4:], 0x7f000000+i)
		k[8], k[9] = 1, 6
		binary.BigEndian.PutUint16(k[10:], 4444)
		if _, exists := original[string(k)]; exists {
			return fmt.Errorf("synthetic identity collision")
		}
		v := make([]byte, info.ValueSize)
		if err := m.Update(k, v, ebpf.UpdateAny); err != nil {
			overflow = err
			break
		}
		inserted = append(inserted, k)
	}
	if !errors.Is(overflow, unix.ENOSPC) && !errors.Is(overflow, unix.E2BIG) {
		return fmt.Errorf("expected capacity failure, got %v after %d inserts", overflow, len(inserted))
	}
	if len(original)+len(inserted) != int(info.MaxEntries) {
		return fmt.Errorf("unexpected occupancy: %d + %d != %d", len(original), len(inserted), info.MaxEntries)
	}
	for k, v := range original {
		got, err := m.LookupBytes([]byte(k))
		if err != nil || !bytes.Equal(v, got) {
			return fmt.Errorf("original entry evicted or altered")
		}
	}
	report := map[string]interface{}{"path": path, "type": info.Type.String(), "maxEntries": info.MaxEntries, "originalEntries": len(original), "syntheticEntries": len(inserted), "error": overflow.Error(), "originalEntriesRetained": true}
	encoded, _ := json.Marshal(report)
	fmt.Println("MAP_FULL", string(encoded))
	select {
	case <-ctx.Done():
		return ctx.Err()
	case <-time.After(*hold):
	}
	for _, k := range inserted {
		if err := m.Delete(k); err != nil && !errors.Is(err, ebpf.ErrKeyNotExist) {
			return err
		}
	}
	inserted = nil
	cm := cluster.NewObject("v1", "ConfigMap", *ns, "policy-map-measurement", nil)
	delete(cm.Object, "spec")
	cm.Object["data"] = cluster.Map{"kind": "cilium-policy-map", "maxEntries": fmt.Sprint(info.MaxEntries), "originalEntries": fmt.Sprint(len(original)), "overflow": overflow.Error(), "oldEntriesRetained": "true", "endpointUID": string(pod.GetUID()), "report": string(encoded)}
	if err := c.Apply(ctx, "configmaps", cm); err != nil {
		return err
	}
	fmt.Println("PASS: real Cilium policy map rejected overflow without FIFO eviction; synthetic entries removed")
	return nil
}
