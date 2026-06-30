# Codex Bootstrap Prompt

You are Codex running inside WSL on my Windows machine. I want you to build an open-source project called CodexDock.

## Goal

Build a Go CLI that lets me control a Codex tmux session running inside WSL from my Mac over SSH.

## Product boundary

- Do not build a VPN.
- Do not clone Tailscale.
- Assume Headscale/Tailscale networking already exists.
- Use SSH for remote control.
- Use tmux for persistent sessions.
- Use Codex CLI as the first supported agent.

## MVP commands

Build the MVP with these commands:

```bash
codexdock init
codexdock doctor
codexdock devices
codexdock sessions
codexdock start <device>
codexdock attach <device>
codexdock send <device> "<prompt>"
codexdock logs <device>
codexdock stop <device>
```

## Repo structure

Create this repo structure:

```text
codexdock/
  README.md
  LICENSE
  go.mod
  cmd/codexdock/main.go
  internal/config/config.go
  internal/ssh/runner.go
  internal/tmux/commands.go
  internal/doctor/doctor.go
  internal/sessions/sessions.go
  examples/config.yaml
  docs/PRD.md
  docs/TECH_SPEC.md
  docs/SETUP.md
```

## Config path

Use this config path:

```text
~/.codexdock/config.yaml
```

## Example config

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

## Implementation requirements

1. Use Go.
2. Use Cobra for CLI.
3. Use system `ssh` through `os/exec` for MVP.
4. Implement safe shell quoting.
5. Validate tmux session names.
6. Avoid shell injection.
7. Make `attach` interactive using `ssh -t`.
8. Make `start` idempotent: if tmux session exists, do not create a duplicate.
9. Make `doctor` return actionable errors.
10. Add unit tests for config parsing, shell quoting, and tmux command generation.

## Build order

Start by creating the Go module, CLI skeleton, config loader, and tmux command builder. Then implement one command at a time in this order:

1. `devices`
2. `doctor`
3. `sessions`
4. `start`
5. `attach`
6. `send`
7. `logs`
8. `stop`

After each command, add a short manual test instruction in the README.

## Acceptance criteria

The MVP is complete when these commands work from Mac:

```bash
codexdock doctor
codexdock devices
codexdock sessions
codexdock start windows-wsl
codexdock attach windows-wsl
codexdock send windows-wsl "hello from mac"
codexdock logs windows-wsl
```

Behavior to verify:

- `start` creates the `codex` tmux session if it does not exist.
- `start` does not create duplicate sessions.
- `attach` opens the remote tmux session interactively.
- `send` injects a prompt into the running session.
- `logs` prints recent terminal output.
- `doctor` gives actionable errors.
