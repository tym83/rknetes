package maxlet

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"time"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"rknetes.su/rknetes/pkg/cluster"
)

// Events are collected from the guarded nested cluster only. The private archive
// is separate from exported evidence; Event messages can contain sensitive data.
func ArchiveEvents(ctx context.Context, c *cluster.Client, directory string) error {
	if err := c.Guard(ctx); err != nil {
		return err
	}
	if err := os.MkdirAll(directory, 0700); err != nil {
		return err
	}
	file, err := os.OpenFile(filepath.Join(directory, "events.jsonl"), os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0600)
	if err != nil {
		return err
	}
	defer file.Close()
	encoder := json.NewEncoder(file)
	for ctx.Err() == nil {
		list, err := c.R("events", "").List(ctx, metav1.ListOptions{})
		if err != nil {
			select {
			case <-ctx.Done():
				return nil
			case <-time.After(time.Second):
			}
			continue
		}
		for _, item := range list.Items {
			if err := encoder.Encode(item.Object); err != nil {
				return err
			}
		}
		watch, err := c.R("events", "").Watch(ctx, metav1.ListOptions{ResourceVersion: list.GetResourceVersion()})
		if err != nil {
			continue
		}
		for event := range watch.ResultChan() {
			if err := encoder.Encode(event.Object); err != nil {
				watch.Stop()
				return err
			}
		}
		watch.Stop()
	}
	return nil
}
