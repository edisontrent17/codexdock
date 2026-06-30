# CodexDock Roadmap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build CodexDock as a Go CLI that creates named CodexDock networks, registers machines by friendly alias, connects by SSH, and controls Codex/tmux sessions while treating Headscale/Tailscale as managed OSS internals.

**Architecture:** The public CLI exposes only CodexDock concepts: `create`, `register`, `machines`, `connect`, `doctor`, and `codex` subcommands. Local state lives in `~/.codexdock/config.yaml`; network reachability and machine status are delegated to a small internal tailnet adapter that shells out to the Tailscale client when present. SSH and tmux are isolated behind focused packages so command generation can be unit tested without real remote hosts.

**Tech Stack:** Go 1.22, Cobra for CLI commands, `gopkg.in/yaml.v3` for config, standard `os/exec` for SSH/Tailscale subprocesses, table-driven Go tests.

---

### Task 1: Repository Scaffold And Plan

**Files:**
- Create: `go.mod`
- Create: `LICENSE`
- Create: `NOTICE`
- Create: `README.md`
- Create: `cmd/codexdock/main.go`
- Create: `internal/cli/root.go`
- Create: `internal/config/config.go`
- Create: `internal/config/config_test.go`
- Create: `internal/tmux/commands.go`
- Create: `internal/tmux/commands_test.go`
- Create: `internal/ssh/runner.go`
- Create: `internal/tailnet/status.go`

- [ ] **Step 1: Write failing config tests**

```go
func TestSaveLoadAndRegisterMachine(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "config.yaml")
	store := config.NewStore(path)
	cfg := config.New()
	cfg.UpsertNetwork(config.Network{Name: "personal"})
	cfg.UpsertMachine("personal", config.Machine{Name: "homepc", SSHUser: "manoj", SSHPort: 22, Role: "codex-host"})
	require.NoError(t, store.Save(cfg))
	loaded, err := store.Load()
	require.NoError(t, err)
	require.Equal(t, "homepc", loaded.Networks["personal"].Machines["homepc"].Name)
}
```

- [ ] **Step 2: Run config tests and verify RED**

Run: `go test ./internal/config -run TestSaveLoadAndRegisterMachine -v`

Expected: FAIL because `internal/config` does not exist yet.

- [ ] **Step 3: Implement config store**

Create `internal/config/config.go` with `Config`, `Network`, `Machine`, `Store`, `Load`, `Save`, `UpsertNetwork`, `UpsertMachine`, and `ResolveMachine`.

- [ ] **Step 4: Run config tests and verify GREEN**

Run: `go test ./internal/config -v`

Expected: PASS.

### Task 2: Safe tmux Command Generation

**Files:**
- Create: `internal/tmux/commands.go`
- Create: `internal/tmux/commands_test.go`

- [ ] **Step 1: Write failing tmux tests**

```go
func TestSendKeysQuotesPrompt(t *testing.T) {
	got, err := tmux.SendKeysCommand("codex", "it's ok")
	require.NoError(t, err)
	require.Equal(t, "tmux send-keys -t codex 'it'\"'\"'s ok' Enter", got)
}
```

- [ ] **Step 2: Run tmux tests and verify RED**

Run: `go test ./internal/tmux -run TestSendKeysQuotesPrompt -v`

Expected: FAIL because `SendKeysCommand` does not exist yet.

- [ ] **Step 3: Implement tmux command helpers**

Create validated helpers for list, start, attach, send, capture, and kill. Validate session names with `^[A-Za-z0-9_-]+$`; quote workspace, prompt, and agent command with POSIX single-quote escaping.

- [ ] **Step 4: Run tmux tests and verify GREEN**

Run: `go test ./internal/tmux -v`

Expected: PASS.

### Task 3: CLI UX And Local State

**Files:**
- Create: `internal/cli/root.go`
- Create: `internal/cli/root_test.go`
- Modify: `cmd/codexdock/main.go`
- Modify: `internal/config/config.go`

- [ ] **Step 1: Write failing CLI tests**

```go
func TestCreateAndRegisterCommandsPersistState(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.yaml")
	root := cli.New(cli.Options{ConfigPath: path, Out: io.Discard, Err: io.Discard})
	root.SetArgs([]string{"create", "personal"})
	require.NoError(t, root.Execute())
	root.SetArgs([]string{"register", "homepc", "personal", "--ssh-user", "manoj"})
	require.NoError(t, root.Execute())
	cfg, err := config.NewStore(path).Load()
	require.NoError(t, err)
	require.Equal(t, "homepc", cfg.Networks["personal"].Machines["homepc"].Name)
}
```

- [ ] **Step 2: Run CLI test and verify RED**

Run: `go test ./internal/cli -run TestCreateAndRegisterCommandsPersistState -v`

Expected: FAIL because CLI package does not exist yet.

- [ ] **Step 3: Implement public command skeleton**

Implement `create`, `register`, `machines`, `doctor`, `connect`, and `codex` subcommands without exposing `tailscale` or `headscale` command nouns.

- [ ] **Step 4: Run CLI tests and verify GREEN**

Run: `go test ./internal/cli -v`

Expected: PASS.

### Task 4: SSH Runner And Connect Workflow

**Files:**
- Create: `internal/ssh/runner.go`
- Create: `internal/ssh/runner_test.go`
- Modify: `internal/cli/root.go`

- [ ] **Step 1: Write failing SSH tests**

```go
func TestBuildSSHArgsIncludesPortAndTarget(t *testing.T) {
	target := ssh.Target{Host: "100.64.0.2", User: "manoj", Port: 2222}
	require.Equal(t, []string{"-p", "2222", "manoj@100.64.0.2"}, ssh.Args(target, false, ""))
}
```

- [ ] **Step 2: Run SSH tests and verify RED**

Run: `go test ./internal/ssh -run TestBuildSSHArgsIncludesPortAndTarget -v`

Expected: FAIL because SSH package does not exist yet.

- [ ] **Step 3: Implement runner**

Implement non-interactive and interactive SSH runners using `exec.Command("ssh", args...)`, with injectable command execution for tests.

- [ ] **Step 4: Run SSH tests and verify GREEN**

Run: `go test ./internal/ssh -v`

Expected: PASS.

### Task 5: Tailnet Adapter And Doctor

**Files:**
- Create: `internal/tailnet/status.go`
- Create: `internal/tailnet/status_test.go`
- Modify: `internal/cli/root.go`

- [ ] **Step 1: Write failing tailnet tests**

```go
func TestParseTailscaleStatusJSON(t *testing.T) {
	status, err := tailnet.ParseStatusJSON([]byte(`{"Self":{"HostName":"macbook"},"Peer":{"abc":{"HostName":"homepc","TailscaleIPs":["100.64.0.2"],"Online":true}}}`))
	require.NoError(t, err)
	require.Equal(t, "100.64.0.2", status.Peers["homepc"].IP)
}
```

- [ ] **Step 2: Run tailnet tests and verify RED**

Run: `go test ./internal/tailnet -run TestParseTailscaleStatusJSON -v`

Expected: FAIL because tailnet package does not exist yet.

- [ ] **Step 3: Implement adapter**

Implement `tailscale status --json` parsing, component detection, and doctor checks that report missing dependencies without exposing separate public Headscale/Tailscale commands.

- [ ] **Step 4: Run tailnet tests and verify GREEN**

Run: `go test ./internal/tailnet -v`

Expected: PASS.

### Task 6: Codex/tmux Workflow

**Files:**
- Modify: `internal/cli/root.go`
- Modify: `internal/tmux/commands.go`
- Add tests in `internal/cli/root_test.go`

- [ ] **Step 1: Write failing tests for Codex subcommands**

```go
func TestCodexSendUsesTmuxSendKeysOverSSH(t *testing.T) {
	recorder := &fakeRunner{}
	root := cli.New(cli.Options{ConfigPath: seededConfig(t), Runner: recorder, Out: io.Discard, Err: io.Discard})
	root.SetArgs([]string{"codex", "send", "homepc", "personal", "continue"})
	require.NoError(t, root.Execute())
	require.Contains(t, recorder.Commands[0], "tmux send-keys -t codex 'continue' Enter")
}
```

- [ ] **Step 2: Run test and verify RED**

Run: `go test ./internal/cli -run TestCodexSendUsesTmuxSendKeysOverSSH -v`

Expected: FAIL because Codex subcommands do not execute tmux commands yet.

- [ ] **Step 3: Implement Codex subcommands**

Implement `codex start`, `codex attach`, `codex send`, and `codex logs` using registered machine SSH metadata and tmux command helpers.

- [ ] **Step 4: Run CLI tests and verify GREEN**

Run: `go test ./internal/cli -v`

Expected: PASS.

### Task 7: Documentation, Licenses, And TrentPlatform Updates

**Files:**
- Modify: `README.md`
- Modify: `NOTICE`
- Create: `docs/roadmap.md`

- [ ] **Step 1: Document public UX**

Document:

```bash
codexdock create personal
codexdock register homepc personal
codexdock machines personal
codexdock connect homepc personal
codexdock codex attach homepc personal
```

- [ ] **Step 2: Preserve upstream notices**

Add BSD 3-Clause notice references for Headscale and Tailscale in `NOTICE`.

- [ ] **Step 3: Verify full test suite**

Run: `go test ./...`

Expected: PASS.

- [ ] **Step 4: Update TrentPlatform**

Use the scoped TrentPlatform PAT to mark implemented roadmap items active/done as supported by the current state, and add an artifact record linking to the implementation plan summary.
