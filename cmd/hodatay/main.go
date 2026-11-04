package main

import (
	"bytes"
	"fmt"
	"io"
	"os"
	"os/exec"
	"strings"
)

// Hodatay retains the upstream client for discovery, transport and structured output.
func main() {
	args := os.Args[1:]
	for i, arg := range args {
		if arg == "max" && i+1 < len(args) {
			server, ca := os.Getenv("HODATAY_MAX_SERVER"), os.Getenv("HODATAY_MAX_CA")
			if server == "" || ca == "" {
				fmt.Fprintln(os.Stderr, "HODATAY_MAX_SERVER and HODATAY_MAX_CA are required")
				os.Exit(2)
			}
			args = append([]string{"--server=" + server, "--certificate-authority=" + ca}, append(args[:i:i], args[i+1:]...)...)
			break
		}
	}

	binary := os.Getenv("HODATAY_KUBECTL")
	if binary == "" {
		binary = "kubectl"
	}
	plainVersion := false
	structured := false
	for _, a := range args {
		if a == "version" {
			plainVersion = true
		}
		if a == "-o" || a == "--output" || strings.HasPrefix(a, "-o=") || strings.HasPrefix(a, "--output=") {
			structured = true
		}
	}
	cmd := exec.Command(binary, args...)
	cmd.Stdin = os.Stdin
	cmd.Stderr = os.Stderr
	if plainVersion && !structured {
		var out bytes.Buffer
		cmd.Stdout = &out
		if err := cmd.Run(); err != nil {
			exit(err)
		}
		for _, line := range strings.Split(out.String(), "\n") {
			if strings.HasPrefix(line, "Client Version:") {
				fmt.Println("Клиент: Кормчий-Ходатай 1.0 (отечественная разработка)")
			} else if strings.HasPrefix(line, "Server Version:") {
				fmt.Println("Сервер: Кормчий-Единое окно 1.0 (отечественная разработка)")
			} else if line != "" {
				fmt.Println(line)
			}
		}
		return
	}
	yaml := false
	for i, a := range args {
		if a == "-o=yaml" || a == "--output=yaml" || ((a == "-o" || a == "--output") && i+1 < len(args) && args[i+1] == "yaml") {
			yaml = true
		}
	}
	if yaml {
		var out bytes.Buffer
		cmd.Stdout = &out
		if err := cmd.Run(); err != nil {
			exit(err)
		}
		for _, line := range strings.Split(out.String(), "\n") {
			if strings.TrimSpace(line) == "metadata:" {
				line += " # деятельность Meta Platforms Inc. признана экстремистской и запрещена на территории РФ"
			}
			fmt.Println(line)
		}
		return
	}
	cmd.Stdout = os.Stdout
	if err := cmd.Run(); err != nil {
		exit(err)
	}
}
func exit(err error) {
	if e, ok := err.(*exec.ExitError); ok {
		os.Exit(e.ExitCode())
	}
	io.WriteString(os.Stderr, err.Error()+"\n")
	os.Exit(1)
}
