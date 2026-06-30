# CodexDock Docs Pack

This zip contains the starter docs for **CodexDock**, a fully open-source remote AI coding session manager for controlling Codex running inside WSL from a Mac.

## Files

```text
docs/PRD.md
docs/TECH_SPEC.md
docs/SETUP.md
prompts/codex-bootstrap.md
examples/config.yaml
```

## How to use with Codex

1. Unzip this into your desired workspace.
2. Open `prompts/codex-bootstrap.md`.
3. Paste that prompt into Codex running inside WSL.
4. Ask Codex to create the project using the docs as source of truth.

## Suggested first command

```bash
mkdir -p ~/code/codexdock
cd ~/code/codexdock
```

Then paste the bootstrap prompt into Codex.
