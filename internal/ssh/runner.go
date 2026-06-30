package ssh

import (
	"bytes"
	"fmt"
	"io"
	"os"
	"os/exec"
	"strconv"
	"strings"
)

type Target struct {
	Host string
	User string
	Port int
}

type Runner interface {
	Run(target Target, command string) (stdout string, stderr string, err error)
	RunInteractive(target Target, command string) error
}

type SystemRunner struct {
	Stdin  io.Reader
	Stdout io.Writer
	Stderr io.Writer
}

func Installed() bool {
	_, err := exec.LookPath("ssh")
	return err == nil
}

func Args(target Target, interactive bool, command string) []string {
	port := target.Port
	if port == 0 {
		port = 22
	}
	args := make([]string, 0, 5)
	if interactive {
		args = append(args, "-t")
	}
	args = append(args, "-p", strconv.Itoa(port), targetSpec(target))
	if command != "" {
		args = append(args, command)
	}
	return args
}

func targetSpec(target Target) string {
	user := strings.TrimSpace(target.User)
	if user == "" {
		return target.Host
	}
	return fmt.Sprintf("%s@%s", user, target.Host)
}

func (r SystemRunner) Run(target Target, command string) (string, string, error) {
	cmd := exec.Command("ssh", Args(target, false, command)...)
	var stdout bytes.Buffer
	var stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	err := cmd.Run()
	return stdout.String(), stderr.String(), err
}

func (r SystemRunner) RunInteractive(target Target, command string) error {
	cmd := exec.Command("ssh", Args(target, true, command)...)
	cmd.Stdin = valueOrDefaultReader(r.Stdin, os.Stdin)
	cmd.Stdout = valueOrDefaultWriter(r.Stdout, os.Stdout)
	cmd.Stderr = valueOrDefaultWriter(r.Stderr, os.Stderr)
	return cmd.Run()
}

func valueOrDefaultReader(value io.Reader, fallback io.Reader) io.Reader {
	if value != nil {
		return value
	}
	return fallback
}

func valueOrDefaultWriter(value io.Writer, fallback io.Writer) io.Writer {
	if value != nil {
		return value
	}
	return fallback
}
