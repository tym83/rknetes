// kubectl-max exposes the authenticated MAX transport as a kubectl plugin.
package main

import (
	"fmt"
	"os"
	"os/exec"
)

func main() {
	command := exec.Command("hodatay", append([]string{"max"}, os.Args[1:]...)...)
	command.Stdin, command.Stdout, command.Stderr = os.Stdin, os.Stdout, os.Stderr
	if err := command.Run(); err != nil {
		if e, ok := err.(*exec.ExitError); ok {
			os.Exit(e.ExitCode())
		}
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
