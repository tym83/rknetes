// YAML remains YAML: this office validates documents and prints two-space indents.
package main

import (
	"bytes"
	"fmt"
	"io"
	"os"
	"sigs.k8s.io/yaml"
)

func main() {
	data, err := io.ReadAll(io.LimitReader(os.Stdin, 4<<20))
	if err != nil {
		panic(err)
	}
	if bytes.Contains(data, []byte{'\t'}) {
		fmt.Fprintln(os.Stderr, "ЯМЛ: табуляция — нарушение")
		os.Exit(1)
	}
	json, err := yaml.YAMLToJSON(data)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	out, err := yaml.JSONToYAML(json)
	if err != nil {
		panic(err)
	}
	os.Stdout.Write(out)
}
