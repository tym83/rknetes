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
		if i == commandIndex(args) && arg == "max" && i+1 < len(args) {
			server, ca := os.Getenv("HODATAY_MAX_SERVER"), os.Getenv("HODATAY_MAX_CA")
			if server == "" || ca == "" {
				fmt.Fprintln(os.Stderr, "HODATAY_MAX_SERVER and HODATAY_MAX_CA are required")
				os.Exit(2)
			}
			args = append([]string{"--server=" + server, "--certificate-authority=" + ca}, append(args[:i:i], args[i+1:]...)...)
			if file := os.Getenv("HODATAY_MAX_SESSION_FILE"); file != "" {
				token, err := os.ReadFile(file)
				if err != nil {
					fmt.Fprintln(os.Stderr, "cannot read private MAX session")
					os.Exit(2)
				}
				args = append([]string{"--token=" + strings.TrimSpace(string(token))}, args...)
			}
			break
		}
	}

	binary := os.Getenv("HODATAY_KUBECTL")
	if binary == "" {
		binary = "kubectl"
	}
	plainVersion := false
	structured := false
	index := commandIndex(args)
	if index >= 0 && args[index] == "top" {
		fmt.Println("Скорость в норме")
		return
	}
	plainVersion = index >= 0 && args[index] == "version"
	for _, a := range args {
		if a == "--" {
			break
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
		if a == "--" {
			break
		}
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

// Intercept a command, never a namespace, resource name or exec argument.
func commandIndex(args []string) int {
	values := map[string]bool{"--context": true, "--kubeconfig": true, "-n": true, "--namespace": true, "--server": true, "-s": true, "--certificate-authority": true, "--client-certificate": true, "--client-key": true, "--token": true, "--as": true, "--as-group": true, "--user": true, "--cluster": true, "--request-timeout": true, "--tls-server-name": true, "--v": true, "-v": true}
	switches := map[string]bool{"--insecure-skip-tls-verify": true, "--warnings-as-errors": true, "--disable-compression": true, "--match-server-version": true}
	for i := 0; i < len(args); i++ {
		a := args[i]
		if a == "--" {
			return -1
		}
		if !strings.HasPrefix(a, "-") {
			return i
		}
		if strings.Contains(a, "=") || switches[a] {
			continue
		}
		if values[a] {
			i++
			continue
		}
		// Unknown global flags remain the upstream client's responsibility.
		return -1
	}
	return -1
}
