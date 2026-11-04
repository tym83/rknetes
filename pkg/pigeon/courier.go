package pigeon

import (
	"context"
	"fmt"
	"math/rand/v2"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// Run carries packet files on a mounted volume. There is no network transport.
func Run(ctx context.Context, spool, destination string, delay time.Duration, loss int) error {
	if destination == "" || filepath.Base(destination) != destination || strings.Contains(destination, "..") {
		return fmt.Errorf("invalid destination namespace")
	}
	if loss < 0 || loss > 100 || delay < 0 {
		return fmt.Errorf("invalid delay or loss")
	}
	inbox := filepath.Join(spool, "in", destination)
	out := filepath.Join(spool, "out", destination)
	lost := filepath.Join(spool, "lost", destination)
	for _, d := range []string{inbox, out, lost} {
		if err := os.MkdirAll(d, 0755); err != nil {
			return err
		}
	}
	tick := time.NewTicker(time.Second)
	defer tick.Stop()
	for {
		entries, err := os.ReadDir(inbox)
		if err != nil {
			return err
		}
		for _, e := range entries {
			if !e.Type().IsRegular() || strings.HasPrefix(e.Name(), ".") {
				continue
			}
			info, err := e.Info()
			if err != nil {
				return err
			}
			if time.Since(info.ModTime()) < delay {
				continue
			}
			target := out
			if rand.IntN(100) < loss {
				target = lost
			}
			if err := os.Rename(filepath.Join(inbox, e.Name()), filepath.Join(target, e.Name())); err != nil {
				return err
			}
			fmt.Printf("packet=%s destination=%s delivered=%v\n", e.Name(), destination, target == out)
		}
		select {
		case <-ctx.Done():
			return nil
		case <-tick.C:
		}
	}
}
