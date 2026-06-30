# CodexDock Setup Guide

This guide sets up the MVP path:

```text
MacBook Pro -> SSH over Headscale/Tailscale network -> WSL Ubuntu -> tmux -> Codex
```

## 1. WSL prerequisites

Inside WSL Ubuntu:

```bash
sudo apt update
sudo apt install -y openssh-server tmux
sudo service ssh start
```

Check SSH server:

```bash
sudo service ssh status
```

Check tmux:

```bash
tmux -V
```

Check Codex:

```bash
command -v codex
```

## 2. Headscale/Tailscale network

For a fully open-source setup:

- Use Headscale as the control server.
- Use the open-source Tailscale daemon/client on WSL and Mac where possible.
- Avoid Tailscale's hosted control server if strict open-source/self-hosting is required.

The CLI should assume the network already exists. It should only validate that the target host is reachable.

## 3. SSH from Mac to WSL

From Mac:

```bash
ssh lakshmi@windows-wsl
```

If that does not work, try the Headscale/Tailscale IP:

```bash
ssh lakshmi@100.x.y.z
```

## 4. Start a manual Codex session

Inside WSL:

```bash
cd ~/code
tmux new -s codex
codex
```

Detach from tmux:

```text
Ctrl-b then d
```

Reattach locally:

```bash
tmux attach -t codex
```

## 5. Use CodexDock once built

Initialize config:

```bash
codexdock init \
  --device windows-wsl \
  --host windows-wsl \
  --ssh-user lakshmi \
  --workspace ~/code \
  --session codex \
  --agent codex
```

When `--network` is omitted, CodexDock uses the default `personal` network.

Check readiness:

```bash
codexdock doctor
codexdock doctor --all
```

Start session:

```bash
codexdock start windows-wsl
```

List sessions:

```bash
codexdock sessions
codexdock sessions windows-wsl
```

Attach:

```bash
codexdock attach windows-wsl
```

Send a prompt:

```bash
codexdock send windows-wsl "summarize the current repo and propose next steps"
```

Show recent output:

```bash
codexdock logs windows-wsl --lines 200
```

## 6. Troubleshooting

### SSH does not connect

Check WSL:

```bash
sudo service ssh status
```

Start it:

```bash
sudo service ssh start
```

Check network:

```bash
tailscale status
```

### tmux session does not exist

Start it:

```bash
codexdock start windows-wsl
```

Or manually:

```bash
tmux new -s codex
```

### Codex command missing

Inside WSL:

```bash
command -v codex
```

Install or fix your PATH before using CodexDock.
