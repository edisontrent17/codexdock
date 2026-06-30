# CodexDock PRD

## 1. Product Name

**CodexDock**

## 2. One-line Description

CodexDock is a fully open-source remote AI coding session manager that lets a user control Codex running inside WSL on a Windows machine from a MacBook over a private Headscale/Tailscale network.

## 3. Problem Statement

I run Codex on my Windows machine inside WSL. When I move to my MacBook, I want to resume, control, and send prompts to the same long-running Codex session without manually handling IPs, reconnecting terminals, or losing session state.

Today, the workable solution is SSH + tmux over a private network, but the experience is rough:

- I need to remember the machine name or IP.
- I need to remember the tmux session name.
- I need to manually attach, detach, and send commands.
- There is no simple view of active Codex sessions.
- There is no productized workflow for “continue the AI coding task from another device.”

## 4. Target User

Primary user:

- A technical product manager, principal engineer, or developer who runs terminal-based AI coding agents such as Codex, Claude Code, Gemini CLI, Aider, or local agents on one machine and wants to control them from another device.

Initial personal setup:

- Host machine: Windows machine with WSL Ubuntu.
- Remote control device: MacBook Pro.
- AI coding tool: Codex CLI running inside WSL.
- Session persistence: tmux.
- Private network: Tailscale open-source client with Headscale as self-hosted control server.
- Remote control: SSH.

## 5. Product Goal

Build a simple open-source tool that makes this workflow feel like:

```bash
codexdock devices
codexdock sessions
codexdock attach windows-wsl
codexdock send windows-wsl "continue from the previous task"
```

Instead of:

```bash
ssh user@100.x.y.z
tmux ls
tmux attach -t codex
tmux send-keys -t codex "..." Enter
```

## 6. Product Principles

1. **Do not rebuild Tailscale**
   - Use open-source Tailscale clients and Headscale for networking.
   - CodexDock should own only the AI session management layer.

2. **Use boring reliable primitives**
   - SSH for remote execution.
   - tmux for persistent terminal sessions.
   - Headscale for open-source coordination.
   - WireGuard/Tailscale data plane for private connectivity.

3. **Local-first and self-hosted**
   - No hosted CodexDock cloud.
   - No proprietary control server dependency.
   - No public exposure of the WSL machine.

4. **Composable**
   - Works with Codex first.
   - Should later support Claude Code, Gemini CLI, Aider, shell tasks, and custom terminal agents.

5. **Small enough for one engineer**
   - MVP should be buildable by one person in days, not months.

## 7. Non-goals

The MVP will not build:

- A VPN.
- A full Tailscale clone.
- A Headscale replacement.
- A browser-based IDE.
- A team collaboration platform.
- Multi-tenant SaaS.
- Mobile app.
- File sync.
- Enterprise device posture management.
- Public tunnel or reverse proxy.

## 8. MVP Scope

### MVP 1: CLI-only CodexDock

CodexDock should provide a CLI on Mac that can:

```bash
codexdock doctor
codexdock devices
codexdock sessions
codexdock attach <device>
codexdock start <device>
codexdock send <device> "<prompt>"
codexdock logs <device>
```

### MVP 1 assumptions

- Headscale is already installed or manually installable.
- Mac and WSL can already join the same Headscale network.
- SSH from Mac to WSL works.
- Codex is already installed inside WSL.
- tmux is installed inside WSL.
- The user has a default session name, such as `codex`.

## 9. User Journeys

### Journey 1: First-time setup

As a user, I want to run:

```bash
codexdock init
```

So that CodexDock creates a local config file with:

- Default WSL host.
- SSH user.
- tmux session name.
- Codex command.
- Optional Headscale login server URL.

Expected config:

```yaml
default_device: windows-wsl
devices:
  windows-wsl:
    host: windows-wsl
    ssh_user: lakshmi
    session_name: codex
    codex_command: codex
    workspace: ~/code
```

### Journey 2: Check system readiness

As a user, I want to run:

```bash
codexdock doctor
```

So that I can verify:

- SSH connectivity works.
- tmux exists on WSL.
- Codex command exists on WSL.
- The target workspace exists.
- The Headscale/Tailscale IP or hostname is reachable.

### Journey 3: Start Codex remotely

As a user, I want to run:

```bash
codexdock start windows-wsl
```

So that CodexDock starts a tmux session named `codex` if it does not already exist.

Behind the scenes:

```bash
tmux new-session -d -s codex -c ~/code 'codex'
```

### Journey 4: Attach to Codex

As a user, I want to run:

```bash
codexdock attach windows-wsl
```

So that my Mac terminal attaches to the remote tmux session.

Behind the scenes:

```bash
ssh -t lakshmi@windows-wsl 'tmux attach -t codex'
```

### Journey 5: Send a prompt without attaching

As a user, I want to run:

```bash
codexdock send windows-wsl "summarize this repo and suggest next tasks"
```

So that the prompt is sent into the Codex tmux session without fully attaching.

Behind the scenes:

```bash
tmux send-keys -t codex "summarize this repo and suggest next tasks" Enter
```

### Journey 6: See running sessions

As a user, I want to run:

```bash
codexdock sessions
```

Expected output:

```text
DEVICE        SESSION   STATUS    LAST_ACTIVE
windows-wsl   codex     running   2m ago
```

## 10. Functional Requirements

### Device management

- CodexDock must support one or more named devices.
- Each device should have:
  - `host`
  - `ssh_user`
  - `port`
  - `workspace`
  - `session_name`
  - `agent_command`

### Session management

- List tmux sessions.
- Start a named session.
- Attach to a named session.
- Send prompt to a named session.
- Capture recent pane output.
- Kill a named session only with explicit confirmation.

### Health checks

`codexdock doctor` should check:

- SSH command exists locally.
- SSH connection to target works.
- tmux exists remotely.
- Codex command exists remotely.
- Workspace exists remotely.
- Optional: `tailscale status` or hostname resolution works.

### Config

Default config path:

```text
~/.codexdock/config.yaml
```

Example:

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

### Logs

For MVP, logs can simply be recent tmux pane capture:

```bash
tmux capture-pane -t codex -p -S -200
```

## 11. Security Requirements

- Do not expose CodexDock publicly.
- Use SSH keys, not passwords.
- Do not store SSH private keys in CodexDock config.
- Do not send prompts over public HTTP.
- Do not run arbitrary commands from a remote web UI in MVP.
- Only run known allowlisted commands:
  - `tmux ls`
  - `tmux new-session`
  - `tmux attach`
  - `tmux send-keys`
  - `tmux capture-pane`
  - `command -v`
  - `test -d`
- Avoid shell injection by escaping user input properly.
- Treat prompt text as untrusted input.

## 12. Open-source Requirements

The product should be open-source end to end.

Allowed dependencies:

- Headscale
- Tailscale open-source daemon/client
- OpenSSH
- tmux
- Go standard library
- Cobra or urfave/cli for CLI
- YAML parser
- Bubble Tea later for TUI

Avoid in MVP:

- Tailscale hosted control plane.
- Closed-source GUI dependency.
- SaaS backend.
- Proprietary relay service.
- Public cloud auth requirement.

## 13. Success Metrics

Personal MVP success:

- I can start Codex on WSL from my Mac.
- I can attach to the same Codex session from my Mac.
- I can detach and later reattach without losing context.
- I can send a prompt from Mac without attaching.
- I can list current Codex sessions.
- I can run the entire setup without depending on Tailscale cloud.

Technical success:

- Setup works across different Wi-Fi networks.
- SSH works over the private Headscale network.
- No public port is exposed.
- Session survives Mac disconnect.
- Session survives terminal close.
- Session survives Mac sleep.
- WSL host can be reconnected after network changes.

## 14. MVP Acceptance Criteria

The MVP is complete when the following commands work from Mac:

```bash
codexdock doctor
codexdock sessions
codexdock start windows-wsl
codexdock attach windows-wsl
codexdock send windows-wsl "hello from mac"
codexdock logs windows-wsl
```

And the following behavior is verified:

- If the `codex` tmux session does not exist, `start` creates it.
- If the session already exists, `start` does not duplicate it.
- `attach` opens the remote tmux session interactively.
- `send` injects a prompt into the running session.
- `logs` prints recent terminal output.
- `doctor` gives actionable errors.

## 15. Future Roadmap

### Phase 2: Better local UX

- TUI dashboard.
- Device selector.
- Active session status.
- Recent output preview.
- One-key attach.
- Prompt history.

### Phase 3: WSL agent

- Install a small daemon inside WSL.
- Expose a local-only or tailnet-only API.
- Remove the need to construct shell commands from Mac.
- Add stronger command allowlisting.

### Phase 4: Embedded tailnet service

- Use tsnet in a Go service.
- Make `codexdockd` appear as its own tailnet node.
- Expose only the CodexDock API, not the whole WSL SSH service.

### Phase 5: Multi-agent support

- Codex
- Claude Code
- Gemini CLI
- Aider
- Shell scripts
- Local LLM agents

## 16. Product Positioning

CodexDock is not a VPN.

CodexDock is not a terminal emulator.

CodexDock is not a Tailscale clone.

CodexDock is:

> An open-source control plane for long-running AI coding sessions across your own machines.

## 17. References

- Tailscale Open Source: https://tailscale.com/opensource
- Tailscale custom control server docs: https://tailscale.com/docs/how-to/set-up-custom-control-server
- Headscale GitHub repository: https://github.com/juanfont/headscale
- Tailscale tsnet docs: https://tailscale.com/docs/features/tsnet
