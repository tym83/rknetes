package flows

import (
	"fmt"
	"io"
	"sort"
	"strings"
)

type Graph map[string]map[string]map[string]int

func (g Graph) Add(from, to, verdict string) {
	if from == "" || to == "" {
		return
	}
	if g[from] == nil {
		g[from] = map[string]map[string]int{}
	}
	if g[from][to] == nil {
		g[from][to] = map[string]int{}
	}
	g[from][to][verdict]++
}

func (g Graph) Print(roots []string, out io.Writer) {
	fmt.Fprintln(out, "Observed root dependency graph (bounded sample; forwarding is not application success):")
	roots = append([]string(nil), roots...)
	sort.Strings(roots)
	seen := map[string]bool{}
	var walk func(string, string)
	walk = func(node, indent string) {
		if seen[node] {
			fmt.Fprintf(out, "%s%s [already visited]\n", indent, node)
			return
		}
		seen[node] = true
		edges := g[node]
		if len(edges) == 0 {
			fmt.Fprintf(out, "%s%s [NO_OBSERVATION of outgoing dependencies]\n", indent, node)
			return
		}
		fmt.Fprintln(out, indent+node)
		targets := make([]string, 0, len(edges))
		for to := range edges {
			targets = append(targets, to)
		}
		sort.Strings(targets)
		for _, to := range targets {
			verdicts := []string{}
			for verdict, count := range edges[to] {
				verdicts = append(verdicts, fmt.Sprintf("%s=%d", verdict, count))
			}
			sort.Strings(verdicts)
			fmt.Fprintf(out, "%s  -> %s [%s]\n", indent, to, strings.Join(verdicts, ", "))
			if len(g[to]) > 0 {
				walk(to, indent+"     ")
			}
		}
	}
	for _, root := range roots {
		walk(root, "")
	}
	fmt.Fprintln(out, "End observed root graph; absent edges are unknown, not proof of reachability.")
}
