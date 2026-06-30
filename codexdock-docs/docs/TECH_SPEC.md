# CodexDock Technical Spec

## 1. Architecture

### MVP Architecture

```text
MacBook Pro
  |
  | codexdock CLI
  | SSH over private Headscale/Tailscale network
  v
Windows machine - WSL Ubuntu
  |
  | sshd
  | tmux
  | Codex CLI
  v
Long-running Codex session
```

## 2. Components

### 2.1 CodexDock CLI

Runs on Mac.

Responsibilities:

- Read config.
- Validate environment.
- Connect to WSL over SSH.
- Execute safe remote tmux commands.
- Attach user to remote tmux session.
- Send prompt text to active tmux session.
- Print recent pane output.

Recommended language:

- Go

Reason:

- Single static binary.
- Easy CLI distribution.
- Good SSH/process handling.
- Later compatibility with tsnet if needed.

Suggested libraries:

- `spf13/cobra` for CLI.
- `gopkg.in/yaml.v3` for config.
- Standard `os/exec` for SSH subprocesses.

MVP can use system SSH instead of implementing SSH protocol directly.

### 2.2 WSL host

Runs inside Ubuntu WSL.

Required tools:

```bash
sudo apt update
sudo apt install -y openssh-server tmux
```

Required runtime:

```bash
codex
```

Required service:

```bash
sudo service ssh start
```

Recommended tmux session:

```bash
tmux new -s codex
```

### 2.3 Network layer

Use:

- Headscale as control server.
- Tailscale open-source client/daemon on WSL.
- Tailscale open-source client/daemon on Mac, avoiding proprietary GUI dependency if strict OSS is required.

Desired device names:

```text
macbook-pro
windows-wsl
```

The CLI should not implement networking. It should assume the private network exists and only validate reachability.

## 3. Repository Structure

```text
codexdock/
  README.md
  LICENSE
  go.mod
  go.sum

  cmd/
    codexdock/
      main.go

  internal/
    config/
      config.go
      config_test.go

    ssh/
      runner.go
      runner_test.go

    tmux/
      commands.go
      commands_test.go

    doctor/
      doctor.go

    sessions/
      sessions.go

  docs/
    PRD.md
    TECH_SPEC.md
    SETUP.md

  prompts/
    codex-bootstrap.md

  examples/
    config.yaml
```

## 4. CLI Commands

### 4.1 `codexdock init`

Purpose:

Create config file.

Command:

```bash
codexdock init
```

Behavior:

- Create `~/.codexdock/config.yaml`.
- Ask for:
  - device name
  - host
  - SSH user
  - SSH port
  - workspace
  - session name
  - agent command
- If config already exists, ask before overwrite.

MVP shortcut:

Allow non-interactive flags:

```bash
codexdock init \
  --device windows-wsl \
  --host windows-wsl \
  --ssh-user lakshmi \
  --workspace ~/code \
  --session codex \
  --agent codex
```

### 4.2 `codexdock doctor`

Purpose:

Check setup readiness.

Command:

```bash
codexdock doctor
```

Checks:

Local:

```bash
command -v ssh
```

Current CLI output uses `ok ssh command found` or `warn ssh command not found`
for this local prerequisite.

Remote:

```bash
ssh <host> 'command -v tmux'
ssh <host> 'command -v codex'
ssh <host> 'test -d ~/code'
```

Output:

```text
✓ config found
✓ ssh command found
✓ can connect to windows-wsl
✓ tmux found
✓ codex found
✓ workspace exists
```

Failure output should be actionable:

```text
✗ tmux not found on windows-wsl
Fix:
  ssh windows-wsl 'sudo apt update && sudo apt install -y tmux'
```

### 4.3 `codexdock devices`

Purpose:

List configured devices.

Command:

```bash
codexdock devices
```

Output:

```text
NAME          HOST          USER      WORKSPACE
windows-wsl   windows-wsl   lakshmi   ~/code
```

### 4.4 `codexdock sessions`

Purpose:

List tmux sessions on target device.

Command:

```bash
codexdock sessions
codexdock sessions windows-wsl
```

Remote command:

```bash
tmux ls
```

Output:

```text
DEVICE        SESSION   STATUS
windows-wsl   codex     running
```

If no sessions:

```text
No tmux sessions found on windows-wsl.
Run:
  codexdock start windows-wsl
```

### 4.5 `codexdock start`

Purpose:

Start Codex in a tmux session.

Command:

```bash
codexdock start windows-wsl
```

Remote behavior:

```bash
tmux has-session -t codex 2>/dev/null || tmux new-session -d -s codex -c ~/code 'codex'
```

Rules:

- Do not create duplicate sessions.
- If session exists, print existing session status.
- If workspace is missing, fail with clear message.
- If Codex command is missing, fail with clear message.

Output:

```text
Started Codex session 'codex' on windows-wsl.
Attach:
  codexdock attach windows-wsl
```

### 4.6 `codexdock attach`

Purpose:

Attach local terminal to remote tmux session.

Command:

```bash
codexdock attach windows-wsl
```

Remote command:

```bash
ssh -t lakshmi@windows-wsl 'tmux attach -t codex'
```

Rules:

- Must be interactive.
- Must use `ssh -t`.
- If session does not exist, suggest `codexdock start`.

### 4.7 `codexdock send`

Purpose:

Send prompt into the active Codex session without attaching.

Command:

```bash
codexdock send windows-wsl "summarize current repo and suggest next task"
```

Remote command:

```bash
tmux send-keys -t codex '<escaped prompt>' Enter
```

Safety:

- Escape single quotes.
- Reject empty prompt.
- Print a warning for very long prompts.
- Do not execute prompt as shell command locally.
- Only pass prompt to `tmux send-keys`.

Output:

```text
Sent prompt to codex on windows-wsl.
```

### 4.8 `codexdock logs`

Purpose:

Show recent terminal output.

Command:

```bash
codexdock logs windows-wsl
codexdock logs windows-wsl --lines 200
```

Remote command:

```bash
tmux capture-pane -t codex -p -S -200
```

Output:

Print captured pane text.

### 4.9 `codexdock stop`

Purpose:

Stop a session.

Command:

```bash
codexdock stop windows-wsl
```

Remote command:

```bash
tmux kill-session -t codex
```

Safety:

- Ask for confirmation unless `--force` is passed.
- Print warning that Codex session will be killed.

## 5. Config Spec

Path:

```text
~/.codexdock/config.yaml
```

Schema:

```yaml
default_device: windows-wsl

devices:
  windows-wsl:
    host: windows-wsl
    ssh_user: lakshmi
    ssh_port: 22
    workspace: ~/code
    session_name: codex
    agent_command: codex
```

Optional future fields:

```yaml
headscale:
  login_server: https://headscale.example.com

devices:
  windows-wsl:
    tags:
      - personal
      - wsl
    agent_type: codex
    log_lines_default: 200
```

## 6. Implementation Details

### SSH runner

Create a helper:

```go
type SSHTarget struct {
    Host string
    User string
    Port int
}

type Runner interface {
    Run(target SSHTarget, command string) (stdout string, stderr string, err error)
    RunInteractive(target SSHTarget, command string) error
}
```

MVP uses:

```bash
ssh -p <port> <user>@<host> '<command>'
```

Interactive attach uses:

```bash
ssh -t -p <port> <user>@<host> '<command>'
```

### tmux commands

Create pure functions that generate remote commands:

```go
func ListSessionsCommand() string
func HasSessionCommand(session string) string
func StartSessionCommand(session, workspace, agentCommand string) string
func AttachCommand(session string) string
func SendKeysCommand(session, prompt string) string
func CapturePaneCommand(session string, lines int) string
func KillSessionCommand(session string) string
```

All user input must be shell-escaped.

### Escaping

Implement a safe shell escape function.

Example:

```go
func ShellQuote(s string) string {
    return "'" + strings.ReplaceAll(s, "'", "'\"'\"'") + "'"
}
```

Use this for:

- workspace
- session name
- prompt
- agent command where applicable

For stricter security, validate session name:

```text
allowed: letters, numbers, dash, underscore
```

Reject:

```text
; | & ` $ ( ) < > newline
```

## 7. Error Handling

Error examples:

### SSH fails

```text
Could not connect to windows-wsl over SSH.

Try:
  ssh lakshmi@windows-wsl

Also check:
  - Is WSL running?
  - Is sshd running inside WSL?
  - Is the Headscale/Tailscale connection active?
```

### tmux missing

```text
tmux is not installed on windows-wsl.

Fix:
  ssh lakshmi@windows-wsl 'sudo apt update && sudo apt install -y tmux'
```

### Codex missing

```text
Codex command was not found on windows-wsl.

Check:
  ssh lakshmi@windows-wsl 'command -v codex'
```

### Session missing

```text
Session 'codex' does not exist.

Start it:
  codexdock start windows-wsl
```

## 8. Testing Strategy

### Unit tests

Test:

- Config parsing.
- Shell escaping.
- tmux command generation.
- Device resolution.
- Error formatting.

### Integration tests

Use local mock commands first.

Later:

- Docker container with sshd and tmux.
- Run CLI against container.
- Verify session start/list/send/logs.

### Manual test checklist

On Mac:

```bash
codexdock doctor
codexdock devices
codexdock sessions
codexdock start windows-wsl
codexdock logs windows-wsl
codexdock send windows-wsl "hello"
codexdock attach windows-wsl
```

Inside WSL:

```bash
tmux ls
tmux capture-pane -t codex -p -S -50
```

## 9. Local Setup Guide

### WSL

```bash
sudo apt update
sudo apt install -y openssh-server tmux
sudo service ssh start
command -v codex
```

Optional:

```bash
tmux new -s codex
```

### Mac

```bash
ssh lakshmi@windows-wsl
```

Then install CodexDock:

```bash
go install github.com/<your-username>/codexdock/cmd/codexdock@latest
```

Initialize:

```bash
codexdock init \
  --device windows-wsl \
  --host windows-wsl \
  --ssh-user lakshmi \
  --workspace ~/code \
  --session codex \
  --agent codex
```

Run:

```bash
codexdock doctor
codexdock start windows-wsl
codexdock attach windows-wsl
```

## 10. Build Plan

### Milestone 1: CLI skeleton

Deliver:

- Go module.
- Cobra CLI.
- `version` command.
- Config loader.

### Milestone 2: SSH runner

Deliver:

- Non-interactive SSH command runner.
- Interactive SSH attach runner.
- Error messages.

### Milestone 3: tmux session commands

Deliver:

- `sessions`
- `start`
- `attach`
- `send`
- `logs`

### Milestone 4: doctor

Deliver:

- Local checks.
- Remote checks.
- Actionable failures.

### Milestone 5: polish

Deliver:

- README.
- Example config.
- Install instructions.
- Manual test checklist.

## 11. Future Technical Options

### WSL agent

Later, add:

```text
codexdockd
```

The daemon can expose:

```text
GET  /sessions
POST /sessions/start
POST /sessions/{id}/send
GET  /sessions/{id}/logs
POST /sessions/{id}/stop
```

The CLI can then call the daemon over tailnet instead of SSH.

### tsnet mode

Future version:

- Embed Tailscale networking directly into `codexdockd`.
- Make the daemon appear as a private tailnet service.
- Avoid exposing full SSH access.
- Keep SSH mode as fallback.

### Web dashboard

Later local dashboard:

```text
localhost:7821
```

Features:

- Device list.
- Session list.
- Prompt box.
- Recent logs.
- Attach button.

## 12. References

- Tailscale Open Source: https://tailscale.com/opensource
- Tailscale custom control server docs: https://tailscale.com/docs/how-to/set-up-custom-control-server
- Headscale GitHub repository: https://github.com/juanfont/headscale
- Tailscale tsnet docs: https://tailscale.com/docs/features/tsnet
