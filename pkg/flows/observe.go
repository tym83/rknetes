// Package flows reads observed packet verdicts from Hubble without changing policy.
package flows

import (
	"context"
	"fmt"
	"io"
	"sort"
	"time"

	flow "github.com/cilium/cilium/api/v1/flow"
	observer "github.com/cilium/cilium/api/v1/observer"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
)

// PrintNamespace uses a trusted local port-forward to Hubble Relay. Packet
// forwarding verdicts are observations, not proof of application success.
func PrintNamespace(ctx context.Context, endpoint, namespace string, out io.Writer) error {
	ctx, cancel := context.WithTimeout(ctx, 15*time.Second)
	defer cancel()
	connection, err := grpc.NewClient(endpoint, grpc.WithTransportCredentials(insecure.NewCredentials()))
	if err != nil {
		return err
	}
	defer connection.Close()
	stream, err := observer.NewObserverClient(connection).GetFlows(ctx, &observer.GetFlowsRequest{
		Number: 1000, Whitelist: []*flow.FlowFilter{{SourcePod: []string{namespace + "/"}}},
	})
	if err != nil {
		return fmt.Errorf("Hubble observation: %w", err)
	}
	counts := map[string]int{}
	total := 0
	for {
		message, err := stream.Recv()
		if err == io.EOF {
			break
		}
		if err != nil {
			return fmt.Errorf("Hubble observation: %w", err)
		}
		f := message.GetFlow()
		if f == nil {
			continue
		}
		source, destination := f.GetSource(), f.GetDestination()
		if source.GetNamespace() != namespace {
			continue
		}
		from := source.GetNamespace() + "/" + source.GetPodName()
		to := destination.GetNamespace() + "/" + destination.GetPodName()
		if destination.GetPodName() == "" {
			to = f.GetIP().GetDestination()
		}
		if svc := f.GetDestinationService(); svc.GetName() != "" {
			to += " (service " + svc.GetNamespace() + "/" + svc.GetName() + ")"
		}
		transport := ""
		if tcp := f.GetL4().GetTCP(); tcp != nil {
			transport = fmt.Sprintf(" TCP/%d", tcp.GetDestinationPort())
		}
		if udp := f.GetL4().GetUDP(); udp != nil {
			transport = fmt.Sprintf(" UDP/%d", udp.GetDestinationPort())
		}
		verdict := f.GetVerdict().String()
		if f.GetVerdict() == flow.Verdict_DROPPED {
			verdict += " " + f.GetDropReasonDesc().String()
		}
		key := fmt.Sprintf("%s -> %s%s [%s]", from, to, transport, verdict)
		counts[key]++
		total++
	}
	keys := make([]string, 0, len(counts))
	for key := range counts {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	fmt.Fprintf(out, "Observed Hubble packet flows: %d records in the recent sample\n", total)
	for _, key := range keys {
		fmt.Fprintf(out, "  %s records=%d\n", key, counts[key])
	}
	return nil
}
