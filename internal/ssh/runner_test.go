package ssh_test

import (
	"os"
	"path/filepath"
	"runtime"
	"testing"

	"github.com/stretchr/testify/require"
	"github.com/trentsoftware/codexdock/internal/ssh"
)

func TestBuildSSHArgsIncludesPortAndTarget(t *testing.T) {
	target := ssh.Target{Host: "100.64.0.2", User: "manoj", Port: 2222}

	require.Equal(t, []string{"-p", "2222", "manoj@100.64.0.2"}, ssh.Args(target, false, ""))
}

func TestBuildInteractiveSSHArgsIncludesTTYAndCommand(t *testing.T) {
	target := ssh.Target{Host: "homepc", User: "manoj", Port: 22}

	require.Equal(t, []string{"-t", "-p", "22", "manoj@homepc", "tmux attach -t codex"}, ssh.Args(target, true, "tmux attach -t codex"))
}

func TestInstalledReportsSSHCommandAvailability(t *testing.T) {
	dir := t.TempDir()
	name := "ssh"
	if runtime.GOOS == "windows" {
		name = "ssh.exe"
	}
	path := filepath.Join(dir, name)
	require.NoError(t, os.WriteFile(path, []byte("#!/bin/sh\n"), 0o755))
	t.Setenv("PATH", dir)

	require.True(t, ssh.Installed())
}

func TestInstalledReportsMissingSSHCommand(t *testing.T) {
	t.Setenv("PATH", t.TempDir())

	require.False(t, ssh.Installed())
}
