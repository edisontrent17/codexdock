#!/usr/bin/env sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP=${TMPDIR:-/tmp}
WORK=$(mktemp -d "$TMP/codexdock-smoke.XXXXXX")
cleanup() {
  rm -rf "$WORK"
}
trap cleanup EXIT INT TERM
CODEXDOCK_TRENT_ENV_FILE="$WORK/default-trent-env-does-not-exist"
export CODEXDOCK_TRENT_ENV_FILE

BIN="$WORK/codexdock"
HOME_DIR="$WORK/home"
mkdir -p "$HOME_DIR"

GOCACHE=${GOCACHE:-/tmp/codexdock-gocache}
GOMODCACHE=${GOMODCACHE:-/tmp/codexdock-gomodcache}
export GOCACHE GOMODCACHE
VERSION=${VERSION:-smoke}
COMMIT=${COMMIT:-smoke}
BUILD_DATE=${BUILD_DATE:-1970-01-01T00:00:00Z}

GOCACHE="$GOCACHE" GOMODCACHE="$GOMODCACHE" VERSION="$VERSION" COMMIT="$COMMIT" BUILD_DATE="$BUILD_DATE" OUT="$BIN" "$ROOT/scripts/build.sh" >/dev/null

"$BIN" version | grep -F "codexdock $VERSION" >/dev/null
"$BIN" version | grep -F "commit $COMMIT" >/dev/null

HOME="$HOME_DIR" "$BIN" init \
  --device homepc \
  --host 100.64.0.2 \
  --ssh-user manoj \
  --workspace "~/code" \
  --session codex \
  --agent codex >"$WORK/init.out"
grep -F "Initialized homepc in personal" "$WORK/init.out" >/dev/null
test -f "$HOME_DIR/.codexdock/config.yaml"

HOME="$HOME_DIR" "$BIN" devices >"$WORK/devices.out"
grep -F "NAME	HOST	USER	ROLE	STATUS" "$WORK/devices.out" >/dev/null
grep -F "homepc	100.64.0.2	manoj	developer" "$WORK/devices.out" >/dev/null

TRIM_HOME_DIR="$WORK/trim-home"
mkdir -p "$TRIM_HOME_DIR"
HOME="$TRIM_HOME_DIR" "$BIN" init \
  --device " trimbox " \
  --host " 100.64.0.4 " \
  --ssh-user " manoj " \
  --role " codex-host " \
  --workspace " ~/trim " \
  --session " codex " \
  --agent " codex --ask " >"$WORK/init-trim.out"
grep -F "Initialized trimbox in personal" "$WORK/init-trim.out" >/dev/null
grep -F "host: 100.64.0.4" "$TRIM_HOME_DIR/.codexdock/config.yaml" >/dev/null
grep -F "ssh_user: manoj" "$TRIM_HOME_DIR/.codexdock/config.yaml" >/dev/null
grep -F "role: codex-host" "$TRIM_HOME_DIR/.codexdock/config.yaml" >/dev/null
grep -F "session_name: codex" "$TRIM_HOME_DIR/.codexdock/config.yaml" >/dev/null
grep -F "agent_command: codex --ask" "$TRIM_HOME_DIR/.codexdock/config.yaml" >/dev/null
grep -F "workspace: ~/trim" "$TRIM_HOME_DIR/.codexdock/config.yaml" >/dev/null

HOME="$HOME_DIR" "$BIN" devices --help >"$WORK/devices-help.out"
grep -F -- "--all" "$WORK/devices-help.out" >/dev/null

HOME="$HOME_DIR" "$BIN" sessions --help >"$WORK/sessions-help.out"
grep -F "sessions [machine]" "$WORK/sessions-help.out" >/dev/null

HOME="$HOME_DIR" "$BIN" stop --help >"$WORK/stop-help.out"
grep -F -- "--force" "$WORK/stop-help.out" >/dev/null
grep -F -- "--yes" "$WORK/stop-help.out" >/dev/null

HOME="$HOME_DIR" "$BIN" doctor >"$WORK/doctor.out"
grep -F "ok ssh command found" "$WORK/doctor.out" >/dev/null
grep -F "managed component tailscale BSD-3-Clause internal" "$WORK/doctor.out" >/dev/null
grep -F "managed component headscale BSD-3-Clause internal" "$WORK/doctor.out" >/dev/null

HOME="$HOME_DIR" "$BIN" doctor --repair-plan --target-os linux --role controller >"$WORK/repair.out"
grep -F "CodexDock repair plan" "$WORK/repair.out" >/dev/null
grep -F "control server" "$WORK/repair.out" >/dev/null
grep -F "sudo apt install -y /tmp/headscale.deb" "$WORK/repair.out" >/dev/null

HOME="$HOME_DIR" "$BIN" doctor --repair-plan --target-os linux --role codex-host >"$WORK/codex-host-repair.out"
grep -F "CodexDock repair plan (codex-host)" "$WORK/codex-host-repair.out" >/dev/null
grep -F "openssh-server" "$WORK/codex-host-repair.out" >/dev/null
grep -F "sudo service ssh start" "$WORK/codex-host-repair.out" >/dev/null

if HOME="$HOME_DIR" "$BIN" doctor --repair-plan --target-os linux --role codex-host --workspace "   " >"$WORK/doctor-blank-workspace.out" 2>"$WORK/doctor-blank-workspace.err"; then
  echo "doctor --repair-plan accepted a blank workspace" >&2
  exit 1
fi
grep -F -- "--workspace cannot be empty" "$WORK/doctor-blank-workspace.err" >/dev/null

HOME="$HOME_DIR" "$BIN" doctor --help >"$WORK/doctor-help.out"
grep -F -- "--all" "$WORK/doctor-help.out" >/dev/null
grep -F -- "--ssh-authorized-key" "$WORK/doctor-help.out" >/dev/null
grep -F -- "--ssh-authorized-key-file" "$WORK/doctor-help.out" >/dev/null

if HOME="$HOME_DIR" "$BIN" doctor --repair-plan --target-os linux --role codex-host --ssh-authorized-key "   " >"$WORK/doctor-blank-key.out" 2>"$WORK/doctor-blank-key.err"; then
  echo "doctor --repair-plan accepted a blank SSH authorized key" >&2
  exit 1
fi
grep -F -- "--ssh-authorized-key cannot be blank" "$WORK/doctor-blank-key.err" >/dev/null

if HOME="$HOME_DIR" "$BIN" doctor --repair-plan --target-os linux --role codex-host --ssh-authorized-key-file "   " >"$WORK/doctor-blank-key-file.out" 2>"$WORK/doctor-blank-key-file.err"; then
  echo "doctor --repair-plan accepted a blank SSH authorized key file path" >&2
  exit 1
fi
grep -F -- "--ssh-authorized-key-file cannot be blank" "$WORK/doctor-blank-key-file.err" >/dev/null

BLANK_FIRST_LINE_KEY_FILE="$WORK/blank-first-line-key.pub"
printf '\nssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICodexDockSmokeKey macbook\n' >"$BLANK_FIRST_LINE_KEY_FILE"
if HOME="$HOME_DIR" "$BIN" doctor --repair-plan --target-os linux --role codex-host --ssh-authorized-key-file "$BLANK_FIRST_LINE_KEY_FILE" >"$WORK/doctor-blank-key-file-first-line.out" 2>"$WORK/doctor-blank-key-file-first-line.err"; then
  echo "doctor --repair-plan accepted an SSH authorized key file with a blank first line" >&2
  exit 1
fi
grep -F -- "SSH authorized key file $BLANK_FIRST_LINE_KEY_FILE first line is empty" "$WORK/doctor-blank-key-file-first-line.err" >/dev/null

HOME="$HOME_DIR" "$BIN" register --help >"$WORK/register-help.out"
grep -F -- "--join" "$WORK/register-help.out" >/dev/null
grep -F -- "--enrollment-key" "$WORK/register-help.out" >/dev/null
grep -F -- "--force" "$WORK/register-help.out" >/dev/null

if HOME="$HOME_DIR" "$BIN" register "   " personal --host 100.64.0.3 --ssh-user manoj >"$WORK/register-blank-machine.out" 2>"$WORK/register-blank-machine.err"; then
  echo "register accepted a blank machine name" >&2
  exit 1
fi
grep -F -- "machine name cannot be blank" "$WORK/register-blank-machine.err" >/dev/null

if HOME="$HOME_DIR" "$BIN" register macbook "   " --control-url https://control.example --ssh-user manoj --join >"$WORK/register-blank-network.out" 2>"$WORK/register-blank-network.err"; then
  echo "register --join accepted a blank network name" >&2
  exit 1
fi
grep -F -- "network name cannot be blank" "$WORK/register-blank-network.err" >/dev/null

if HOME="$HOME_DIR" "$BIN" register macbook personal --control-url https://control.example --ssh-user manoj --join --enrollment-key "   " >"$WORK/register-blank-key.out" 2>"$WORK/register-blank-key.err"; then
  echo "register --join accepted a blank enrollment key" >&2
  exit 1
fi
grep -F -- "--enrollment-key cannot be blank" "$WORK/register-blank-key.err" >/dev/null

HOME="$HOME_DIR" "$BIN" create --help >"$WORK/create-help.out"
grep -F -- "--provision" "$WORK/create-help.out" >/dev/null

if HOME="$HOME_DIR" "$BIN" create "   " >"$WORK/create-blank-network.out" 2>"$WORK/create-blank-network.err"; then
  echo "create accepted a blank network name" >&2
  exit 1
fi
grep -F -- "network name cannot be blank" "$WORK/create-blank-network.err" >/dev/null

HOME="$HOME_DIR" "$BIN" adopt --help >"$WORK/adopt-help.out"
grep -F "Adopt a visible private-network peer" "$WORK/adopt-help.out" >/dev/null
grep -F -- "--force" "$WORK/adopt-help.out" >/dev/null

if HOME="$HOME_DIR" "$BIN" adopt "   " --ssh-user manoj >"$WORK/adopt-blank-machine.out" 2>"$WORK/adopt-blank-machine.err"; then
  echo "adopt accepted a blank machine name" >&2
  exit 1
fi
grep -F -- "machine name cannot be blank" "$WORK/adopt-blank-machine.err" >/dev/null

HOME="$HOME_DIR" "$BIN" invite --help >"$WORK/invite-help.out"
grep -F "Issue a CodexDock enrollment key" "$WORK/invite-help.out" >/dev/null
grep -F -- "--ttl" "$WORK/invite-help.out" >/dev/null

if HOME="$HOME_DIR" "$BIN" invite personal --ttl "   " >"$WORK/invite-blank-ttl.out" 2>"$WORK/invite-blank-ttl.err"; then
  echo "invite accepted a blank ttl" >&2
  exit 1
fi
grep -F -- "--ttl cannot be blank" "$WORK/invite-blank-ttl.err" >/dev/null

if HOME="$HOME_DIR" "$BIN" connect "   " personal >"$WORK/connect-blank-machine.out" 2>"$WORK/connect-blank-machine.err"; then
  echo "connect accepted a blank machine name" >&2
  exit 1
fi
grep -F -- "machine name cannot be blank" "$WORK/connect-blank-machine.err" >/dev/null

if HOME="$HOME_DIR" "$BIN" codex start homepc "   " >"$WORK/codex-start-blank-network.out" 2>"$WORK/codex-start-blank-network.err"; then
  echo "codex start accepted a blank network name" >&2
  exit 1
fi
grep -F -- "network name cannot be blank" "$WORK/codex-start-blank-network.err" >/dev/null

DIST="$WORK/dist" TARGETS="linux/amd64" VERSION="$VERSION" COMMIT="$COMMIT" BUILD_DATE="$BUILD_DATE" "$ROOT/scripts/package.sh" >"$WORK/package.out"
test -f "$WORK/dist/codexdock_${VERSION}_linux_amd64.tar.gz"
test -f "$WORK/dist/codexdock_${VERSION}_linux_amd64.tar.gz.sha256"
grep -F "codexdock_${VERSION}_linux_amd64.tar.gz" "$WORK/dist/codexdock_${VERSION}_linux_amd64.tar.gz.sha256" >/dev/null
tar -tzf "$WORK/dist/codexdock_${VERSION}_linux_amd64.tar.gz" | grep -F "codexdock_${VERSION}_linux_amd64/THIRD_PARTY_NOTICES.md" >/dev/null
tar -xOf "$WORK/dist/codexdock_${VERSION}_linux_amd64.tar.gz" "codexdock_${VERSION}_linux_amd64/THIRD_PARTY_NOTICES.md" >"$WORK/third-party-notices.out"
grep -F "Tailscale" "$WORK/third-party-notices.out" >/dev/null
grep -F "Headscale" "$WORK/third-party-notices.out" >/dev/null
grep -F "BSD 3-Clause" "$WORK/third-party-notices.out" >/dev/null

DIST="$WORK/repro-a" TARGETS="linux/amd64" VERSION=repro COMMIT=repro BUILD_DATE=2026-06-29T00:00:00Z "$ROOT/scripts/package.sh" >"$WORK/repro-a.out"
sleep 1
DIST="$WORK/repro-b" TARGETS="linux/amd64" VERSION=repro COMMIT=repro BUILD_DATE=2026-06-29T00:00:00Z "$ROOT/scripts/package.sh" >"$WORK/repro-b.out"
sha256sum "$WORK/repro-a/codexdock_repro_linux_amd64.tar.gz" | sed -n '1s/[[:space:]].*//p' >"$WORK/repro-a.sha"
sha256sum "$WORK/repro-b/codexdock_repro_linux_amd64.tar.gz" | sed -n '1s/[[:space:]].*//p' >"$WORK/repro-b.sha"
cmp "$WORK/repro-a.sha" "$WORK/repro-b.sha"

INSTALL_PREFIX="$WORK/install"
PREFIX="$INSTALL_PREFIX" "$ROOT/scripts/install.sh" "$WORK/dist/codexdock_${VERSION}_linux_amd64.tar.gz" >"$WORK/install.out"
grep -F "installed $INSTALL_PREFIX/bin/codexdock" "$WORK/install.out" >/dev/null
test -x "$INSTALL_PREFIX/bin/codexdock"
"$INSTALL_PREFIX/bin/codexdock" version | grep -F "codexdock $VERSION" >/dev/null

"$ROOT/scripts/e2e-remote.sh" --print-plan >"$WORK/e2e-plan.out"
grep -F "Remote E2E plan" "$WORK/e2e-plan.out" >/dev/null
grep -F "report directory:" "$WORK/e2e-plan.out" >/dev/null
grep -F "CODEXDOCK_REPORT_DIR" "$WORK/e2e-plan.out" >/dev/null
grep -F "CODEXDOCK_SSH_AUTHORIZED_KEY" "$WORK/e2e-plan.out" >/dev/null
grep -F "CODEXDOCK_SSH_AUTHORIZED_KEY_FILE" "$WORK/e2e-plan.out" >/dev/null
grep -F "workspace: ~/code" "$WORK/e2e-plan.out" >/dev/null
grep -F "session: codexdock-e2e" "$WORK/e2e-plan.out" >/dev/null
grep -F 'codexdock doctor --repair-plan --target-os linux --role codex-host --workspace "~/code"' "$WORK/e2e-plan.out" >/dev/null
grep -F "CODEXDOCK_PREPARE=1 runs codexdock doctor homepc --repair --yes --target-os linux --role codex-host" "$WORK/e2e-plan.out" >/dev/null
grep -F "codexdock doctor homepc" "$WORK/e2e-plan.out" >/dev/null
grep -F "codexdock doctor --all" "$WORK/e2e-plan.out" >/dev/null
grep -F "codexdock sessions" "$WORK/e2e-plan.out" >/dev/null
grep -F "codexdock stop homepc --force" "$WORK/e2e-plan.out" >/dev/null

"$ROOT/scripts/e2e-remote.sh" --help >"$WORK/e2e-help.out"
grep -F "CODEXDOCK_BIN" "$WORK/e2e-help.out" >/dev/null

CODEXDOCK_CONTROL_URL=https://control.example "$ROOT/scripts/e2e-remote.sh" --print-plan >"$WORK/e2e-plan-control-url.out"
grep -F "codexdock init --network personal --machine homepc --host <CODEXDOCK_HOST> --ssh-user <CODEXDOCK_USER> --ssh-port 22 --control-url https://control.example --workspace" "$WORK/e2e-plan-control-url.out" >/dev/null

CODEXDOCK_ADOPT=1 "$ROOT/scripts/e2e-remote.sh" --print-plan >"$WORK/e2e-adopt-plan.out"
grep -F "codexdock adopt homepc" "$WORK/e2e-adopt-plan.out" >/dev/null
grep -F "codexdock stop homepc --force" "$WORK/e2e-adopt-plan.out" >/dev/null

PUBLIC_KEY_FILE="$WORK/id_ed25519.pub"
cat >"$PUBLIC_KEY_FILE" <<'EOF'
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICodexDockSmokeKey macbook
EOF
RUNBOOK_DIR="$WORK/e2e-runbook"
CODEXDOCK_REPORT_DIR="$RUNBOOK_DIR" \
  CODEXDOCK_HOST=100.64.0.2 \
  CODEXDOCK_USER=manoj \
  CODEXDOCK_PREPARE=1 \
  CODEXDOCK_SSH_AUTHORIZED_KEY_FILE="$PUBLIC_KEY_FILE" \
  "$ROOT/scripts/e2e-remote.sh" --write-runbook >"$WORK/e2e-runbook.out"
grep -F "remote e2e runbook written" "$WORK/e2e-runbook.out" >/dev/null
test -x "$RUNBOOK_DIR/mac-preflight.sh"
test -x "$RUNBOOK_DIR/mac-run.sh"
test -x "$RUNBOOK_DIR/mac-stage-wsl-codexdock.sh"
test -x "$RUNBOOK_DIR/wsl-install-codexdock.sh"
test -x "$RUNBOOK_DIR/wsl-preflight.sh"
test -x "$RUNBOOK_DIR/wsl-prepare-plan.sh"
test -x "$RUNBOOK_DIR/wsl-prepare.sh"
test -x "$RUNBOOK_DIR/finalize-trent.sh"
sh -n "$RUNBOOK_DIR/mac-preflight.sh"
sh -n "$RUNBOOK_DIR/mac-run.sh"
sh -n "$RUNBOOK_DIR/mac-stage-wsl-codexdock.sh"
sh -n "$RUNBOOK_DIR/wsl-install-codexdock.sh"
sh -n "$RUNBOOK_DIR/wsl-preflight.sh"
sh -n "$RUNBOOK_DIR/wsl-prepare-plan.sh"
sh -n "$RUNBOOK_DIR/wsl-prepare.sh"
sh -n "$RUNBOOK_DIR/finalize-trent.sh"
grep -F "CODEXDOCK_HOST='100.64.0.2'" "$RUNBOOK_DIR/mac-run.sh" >/dev/null
grep -F "CODEXDOCK_USER='manoj'" "$RUNBOOK_DIR/mac-run.sh" >/dev/null
grep -F "CODEXDOCK_REPORT_DIR='$RUNBOOK_DIR'" "$RUNBOOK_DIR/mac-run.sh" >/dev/null
grep -F "CODEXDOCK_REQUIRE_SCP='1'" "$RUNBOOK_DIR/mac-preflight.sh" >/dev/null
grep -F "GOCACHE='/tmp/codexdock-gocache'" "$RUNBOOK_DIR/mac-preflight.sh" >/dev/null
grep -F "GOMODCACHE='/tmp/codexdock-gomodcache'" "$RUNBOOK_DIR/mac-preflight.sh" >/dev/null
grep -F "GOCACHE='/tmp/codexdock-gocache'" "$RUNBOOK_DIR/mac-run.sh" >/dev/null
grep -F "GOMODCACHE='/tmp/codexdock-gomodcache'" "$RUNBOOK_DIR/mac-run.sh" >/dev/null
grep -F "GOOS='linux'" "$RUNBOOK_DIR/mac-stage-wsl-codexdock.sh" >/dev/null
grep -F "GOARCH='amd64'" "$RUNBOOK_DIR/mac-stage-wsl-codexdock.sh" >/dev/null
grep -F "OUT='$RUNBOOK_DIR/codexdock-linux-amd64'" "$RUNBOOK_DIR/mac-stage-wsl-codexdock.sh" >/dev/null
grep -F "scp -P '22' '$RUNBOOK_DIR/codexdock-linux-amd64' 'manoj@100.64.0.2:/tmp/codexdock'" "$RUNBOOK_DIR/mac-stage-wsl-codexdock.sh" >/dev/null
grep -F "ssh -p '22' 'manoj@100.64.0.2'" "$RUNBOOK_DIR/mac-stage-wsl-codexdock.sh" >/dev/null
grep -F "OUT=\"\$HOME/.local/bin/codexdock\"" "$RUNBOOK_DIR/wsl-install-codexdock.sh" >/dev/null
grep -F "./scripts/build.sh" "$RUNBOOK_DIR/wsl-install-codexdock.sh" >/dev/null
grep -F '"$HOME/.local/bin/codexdock" version' "$RUNBOOK_DIR/wsl-install-codexdock.sh" >/dev/null
grep -F "wsl_preflight.txt" "$RUNBOOK_DIR/wsl-preflight.sh" >/dev/null
grep -F "private_network_client=\$(command_status tailscale)" "$RUNBOOK_DIR/wsl-preflight.sh" >/dev/null
grep -F "ssh_listener=\$(ssh_listener_status)" "$RUNBOOK_DIR/wsl-preflight.sh" >/dev/null
grep -F "WORKSPACE='~/code'" "$RUNBOOK_DIR/wsl-preflight.sh" >/dev/null
grep -F "INSTALL='$RUNBOOK_DIR/wsl-install-codexdock.sh'" "$RUNBOOK_DIR/wsl-preflight.sh" >/dev/null
grep -F "PREPARE_PLAN='$RUNBOOK_DIR/wsl-prepare-plan.sh'" "$RUNBOOK_DIR/wsl-preflight.sh" >/dev/null
grep -F "PREPARE='$RUNBOOK_DIR/wsl-prepare.sh'" "$RUNBOOK_DIR/wsl-preflight.sh" >/dev/null
grep -F 'run %s --yes' "$RUNBOOK_DIR/wsl-preflight.sh" >/dev/null
grep -F 'printf "%s/%s" "$HOME" "${WORKSPACE#\~/}"' "$RUNBOOK_DIR/wsl-preflight.sh" >/dev/null
grep -F '${WORKSPACE#\~/}' "$RUNBOOK_DIR/wsl-preflight.sh" >/dev/null
grep -F 'workspace=$WORKSPACE' "$RUNBOOK_DIR/wsl-preflight.sh" >/dev/null
grep -F "codexdock_bin=\$(codexdock_bin_status)" "$RUNBOOK_DIR/wsl-preflight.sh" >/dev/null
grep -F 'next_action=$(next_action)' "$RUNBOOK_DIR/wsl-preflight.sh" >/dev/null
grep -F 'next=$next_action' "$RUNBOOK_DIR/wsl-preflight.sh" >/dev/null
grep -F 'printf "report: %s\n" "$REPORT"' "$RUNBOOK_DIR/wsl-preflight.sh" >/dev/null
grep -F 'printf "next: %s\n" "$next_action"' "$RUNBOOK_DIR/wsl-preflight.sh" >/dev/null
grep -F "./scripts/e2e-remote.sh --preflight" "$RUNBOOK_DIR/mac-preflight.sh" >/dev/null
grep -F "./scripts/e2e-remote.sh" "$RUNBOOK_DIR/mac-run.sh" >/dev/null
grep -F 'CODEXDOCK_BIN=${CODEXDOCK_BIN:-"$HOME/.local/bin/codexdock"}' "$RUNBOOK_DIR/wsl-prepare.sh" >/dev/null
grep -F "REPORT='$RUNBOOK_DIR/wsl_prepare_plan.txt'" "$RUNBOOK_DIR/wsl-prepare-plan.sh" >/dev/null
grep -F 'printf "report: %s\n" "$REPORT"' "$RUNBOOK_DIR/wsl-prepare-plan.sh" >/dev/null
grep -F '"$CODEXDOCK_BIN" doctor --repair-plan --target-os linux --role codex-host --workspace' "$RUNBOOK_DIR/wsl-prepare-plan.sh" >/dev/null
if grep -F -- "--repair --yes" "$RUNBOOK_DIR/wsl-prepare-plan.sh" >/dev/null; then
  echo "wsl-prepare-plan.sh must not run privileged repair steps" >&2
  exit 1
fi
grep -F "REPORT='$RUNBOOK_DIR/wsl_prepare.txt'" "$RUNBOOK_DIR/wsl-prepare.sh" >/dev/null
grep -F 'CODEXDOCK_WSL_PREPARE_YES' "$RUNBOOK_DIR/wsl-prepare.sh" >/dev/null
grep -F 'usage: $0 [--yes]' "$RUNBOOK_DIR/wsl-prepare.sh" >/dev/null
grep -F 'refusing to run privileged WSL prepare without --yes' "$RUNBOOK_DIR/wsl-prepare.sh" >/dev/null
grep -F 'printf "report: %s\n" "$REPORT"' "$RUNBOOK_DIR/wsl-prepare.sh" >/dev/null
grep -F '"$CODEXDOCK_BIN" doctor --repair --yes --target-os linux --role codex-host --workspace' "$RUNBOOK_DIR/wsl-prepare.sh" >/dev/null
grep -F 'CODEXDOCK_TRENT_ENV_FILE=${CODEXDOCK_TRENT_ENV_FILE:-.dev-logs/trent-codexdock.env}' "$RUNBOOK_DIR/finalize-trent.sh" >/dev/null
grep -F 'set -a' "$RUNBOOK_DIR/finalize-trent.sh" >/dev/null
grep -F '. "$CODEXDOCK_TRENT_ENV_FILE"' "$RUNBOOK_DIR/finalize-trent.sh" >/dev/null
grep -F 'set +a' "$RUNBOOK_DIR/finalize-trent.sh" >/dev/null
grep -F "./scripts/trent-finalize-e2e.sh '$RUNBOOK_DIR'" "$RUNBOOK_DIR/finalize-trent.sh" >/dev/null
grep -F "Run on the Mac" "$RUNBOOK_DIR/runbook.txt" >/dev/null
grep -F "Run inside WSL" "$RUNBOOK_DIR/runbook.txt" >/dev/null
grep -F "If SSH into WSL is not ready yet, install CodexDock from inside WSL first:" "$RUNBOOK_DIR/runbook.txt" >/dev/null
grep -F "$RUNBOOK_DIR/wsl-install-codexdock.sh" "$RUNBOOK_DIR/runbook.txt" >/dev/null
grep -F "Check WSL readiness without sudo:" "$RUNBOOK_DIR/runbook.txt" >/dev/null
grep -F "$RUNBOOK_DIR/wsl-preflight.sh" "$RUNBOOK_DIR/runbook.txt" >/dev/null
grep -F "The WSL preflight report records the next local action as next=." "$RUNBOOK_DIR/runbook.txt" >/dev/null
grep -F "Inspect WSL prepare commands without running privileged steps:" "$RUNBOOK_DIR/runbook.txt" >/dev/null
grep -F "$RUNBOOK_DIR/wsl-prepare-plan.sh" "$RUNBOOK_DIR/runbook.txt" >/dev/null
grep -F "WSL prepare scripts write wsl_prepare_plan.txt and wsl_prepare.txt." "$RUNBOOK_DIR/runbook.txt" >/dev/null
grep -F "The privileged WSL prepare script requires --yes or CODEXDOCK_WSL_PREPARE_YES=1." "$RUNBOOK_DIR/runbook.txt" >/dev/null
grep -F "$RUNBOOK_DIR/wsl-prepare.sh --yes" "$RUNBOOK_DIR/runbook.txt" >/dev/null
grep -F "Install the latest CodexDock binary into WSL from the Mac" "$RUNBOOK_DIR/runbook.txt" >/dev/null
grep -F "Source TrentPlatform bootstrap env" "$RUNBOOK_DIR/runbook.txt" >/dev/null

RUNBOOK_BIN_DIR="$WORK/e2e-runbook-bin"
CODEXDOCK_REPORT_DIR="$RUNBOOK_BIN_DIR" \
  CODEXDOCK_HOST=100.64.0.2 \
  CODEXDOCK_USER=manoj \
  CODEXDOCK_BIN="$BIN" \
  "$ROOT/scripts/e2e-remote.sh" --write-runbook >"$WORK/e2e-runbook-bin.out"
grep -F "remote e2e runbook written" "$WORK/e2e-runbook-bin.out" >/dev/null
grep -F "CODEXDOCK_BIN='$BIN'" "$RUNBOOK_BIN_DIR/mac-preflight.sh" >/dev/null
grep -F "CODEXDOCK_BIN='$BIN'" "$RUNBOOK_BIN_DIR/mac-run.sh" >/dev/null

TRIMMED_RUNBOOK_DIR="$WORK/e2e-runbook-trimmed-env"
CODEXDOCK_REPORT_DIR="$TRIMMED_RUNBOOK_DIR" \
  CODEXDOCK_NETWORK=" personal " \
  CODEXDOCK_MACHINE=" homepc " \
  CODEXDOCK_HOST=" 100.64.0.2 " \
  CODEXDOCK_USER=" manoj " \
  CODEXDOCK_ADOPT=" 0 " \
  CODEXDOCK_CONTROL_URL=" https://control.example " \
  CODEXDOCK_PREPARE=" 1 " \
  CODEXDOCK_SSH_PORT=" 2222 " \
  CODEXDOCK_WORKSPACE=" ~/code " \
  CODEXDOCK_SESSION=" codexdock-e2e " \
  CODEXDOCK_AGENT=" codex --ask " \
  CODEXDOCK_PROMPT=" codexdock smoke ping " \
  CODEXDOCK_LOG_LINES=" 40 " \
  CODEXDOCK_SSH_AUTHORIZED_KEY_FILE=" $PUBLIC_KEY_FILE " \
  CODEXDOCK_REQUIRE_SCP=" 0 " \
  CODEXDOCK_TARGET_ARCH=" amd64 " \
  "$ROOT/scripts/e2e-remote.sh" --write-runbook >"$WORK/e2e-runbook-trimmed-env.out"
grep -F "remote e2e runbook written" "$WORK/e2e-runbook-trimmed-env.out" >/dev/null
grep -F "network=personal" "$TRIMMED_RUNBOOK_DIR/context.txt" >/dev/null
grep -F "machine=homepc" "$TRIMMED_RUNBOOK_DIR/context.txt" >/dev/null
grep -F "host=100.64.0.2" "$TRIMMED_RUNBOOK_DIR/context.txt" >/dev/null
grep -F "control_url=https://control.example" "$TRIMMED_RUNBOOK_DIR/context.txt" >/dev/null
grep -F "ssh_user=manoj" "$TRIMMED_RUNBOOK_DIR/context.txt" >/dev/null
grep -F "ssh_port=2222" "$TRIMMED_RUNBOOK_DIR/context.txt" >/dev/null
grep -F "adopt=0" "$TRIMMED_RUNBOOK_DIR/context.txt" >/dev/null
grep -F "prepare=1" "$TRIMMED_RUNBOOK_DIR/context.txt" >/dev/null
grep -F "workspace=~/code" "$TRIMMED_RUNBOOK_DIR/context.txt" >/dev/null
grep -F "session=codexdock-e2e" "$TRIMMED_RUNBOOK_DIR/context.txt" >/dev/null
grep -F "agent=codex --ask" "$TRIMMED_RUNBOOK_DIR/context.txt" >/dev/null
grep -F "prompt=codexdock smoke ping" "$TRIMMED_RUNBOOK_DIR/context.txt" >/dev/null
grep -F "log_lines=40" "$TRIMMED_RUNBOOK_DIR/context.txt" >/dev/null
grep -F "require_scp=0" "$TRIMMED_RUNBOOK_DIR/context.txt" >/dev/null
grep -F "target_arch=amd64" "$TRIMMED_RUNBOOK_DIR/context.txt" >/dev/null
grep -F "CODEXDOCK_HOST='100.64.0.2'" "$TRIMMED_RUNBOOK_DIR/mac-run.sh" >/dev/null
grep -F "CODEXDOCK_USER='manoj'" "$TRIMMED_RUNBOOK_DIR/mac-run.sh" >/dev/null
grep -F "CODEXDOCK_CONTROL_URL='https://control.example'" "$TRIMMED_RUNBOOK_DIR/mac-run.sh" >/dev/null
grep -F "CODEXDOCK_PREPARE='1'" "$TRIMMED_RUNBOOK_DIR/mac-run.sh" >/dev/null
grep -F "CODEXDOCK_SSH_PORT='2222'" "$TRIMMED_RUNBOOK_DIR/mac-run.sh" >/dev/null
grep -F "CODEXDOCK_WORKSPACE='~/code'" "$TRIMMED_RUNBOOK_DIR/mac-run.sh" >/dev/null
grep -F "CODEXDOCK_SESSION='codexdock-e2e'" "$TRIMMED_RUNBOOK_DIR/mac-run.sh" >/dev/null
grep -F "CODEXDOCK_AGENT='codex --ask'" "$TRIMMED_RUNBOOK_DIR/mac-run.sh" >/dev/null
grep -F "CODEXDOCK_PROMPT='codexdock smoke ping'" "$TRIMMED_RUNBOOK_DIR/mac-run.sh" >/dev/null
grep -F "CODEXDOCK_LOG_LINES='40'" "$TRIMMED_RUNBOOK_DIR/mac-run.sh" >/dev/null
grep -F "CODEXDOCK_SSH_AUTHORIZED_KEY_FILE='$PUBLIC_KEY_FILE'" "$TRIMMED_RUNBOOK_DIR/mac-run.sh" >/dev/null
grep -F "CODEXDOCK_REQUIRE_SCP='1'" "$TRIMMED_RUNBOOK_DIR/mac-preflight.sh" >/dev/null
grep -F "GOARCH='amd64'" "$TRIMMED_RUNBOOK_DIR/mac-stage-wsl-codexdock.sh" >/dev/null
grep -F "scp -P '2222' '$TRIMMED_RUNBOOK_DIR/codexdock-linux-amd64' 'manoj@100.64.0.2:/tmp/codexdock'" "$TRIMMED_RUNBOOK_DIR/mac-stage-wsl-codexdock.sh" >/dev/null

BAD_FLAGS_RUNBOOK_DIR="$WORK/e2e-runbook-bad-flags"
if CODEXDOCK_REPORT_DIR="$BAD_FLAGS_RUNBOOK_DIR" \
  CODEXDOCK_HOST=100.64.0.2 \
  CODEXDOCK_USER=manoj \
  CODEXDOCK_ADOPT=maybe \
  CODEXDOCK_PREPARE=later \
  CODEXDOCK_REQUIRE_SCP=required \
  "$ROOT/scripts/e2e-remote.sh" --write-runbook >"$WORK/e2e-runbook-bad-flags.out" 2>&1; then
  echo "expected remote E2E runbook generation to reject invalid flag values" >&2
  exit 1
fi
grep -F "CODEXDOCK_ADOPT must be 0 or 1" "$WORK/e2e-runbook-bad-flags.out" >/dev/null
grep -F "CODEXDOCK_PREPARE must be 0 or 1" "$WORK/e2e-runbook-bad-flags.out" >/dev/null
grep -F "CODEXDOCK_REQUIRE_SCP must be 0 or 1" "$WORK/e2e-runbook-bad-flags.out" >/dev/null
test ! -e "$BAD_FLAGS_RUNBOOK_DIR/context.txt"
test ! -e "$BAD_FLAGS_RUNBOOK_DIR/wsl-prepare.sh"

BAD_CONTROL_URL_RUNBOOK_DIR="$WORK/e2e-runbook-bad-control-url"
if CODEXDOCK_REPORT_DIR="$BAD_CONTROL_URL_RUNBOOK_DIR" \
  CODEXDOCK_HOST=100.64.0.2 \
  CODEXDOCK_USER=manoj \
  CODEXDOCK_CONTROL_URL="   " \
  "$ROOT/scripts/e2e-remote.sh" --write-runbook >"$WORK/e2e-runbook-bad-control-url.out" 2>&1; then
  echo "expected remote E2E runbook generation to reject blank control URL" >&2
  exit 1
fi
grep -F "CODEXDOCK_CONTROL_URL cannot be blank" "$WORK/e2e-runbook-bad-control-url.out" >/dev/null
test ! -e "$BAD_CONTROL_URL_RUNBOOK_DIR/context.txt"
test ! -e "$BAD_CONTROL_URL_RUNBOOK_DIR/wsl-prepare.sh"

BAD_TARGET_RUNBOOK_DIR="$WORK/e2e-runbook-bad-target"
if CODEXDOCK_REPORT_DIR="$BAD_TARGET_RUNBOOK_DIR" \
  CODEXDOCK_HOST="   " \
  CODEXDOCK_USER="   " \
  "$ROOT/scripts/e2e-remote.sh" --write-runbook >"$WORK/e2e-runbook-bad-target.out" 2>&1; then
  echo "expected remote E2E runbook generation to reject blank target inputs" >&2
  exit 1
fi
grep -F "CODEXDOCK_HOST cannot be blank" "$WORK/e2e-runbook-bad-target.out" >/dev/null
grep -F "CODEXDOCK_USER cannot be blank" "$WORK/e2e-runbook-bad-target.out" >/dev/null
test ! -e "$BAD_TARGET_RUNBOOK_DIR/context.txt"
test ! -e "$BAD_TARGET_RUNBOOK_DIR/wsl-prepare.sh"

BAD_PROFILE_RUNBOOK_DIR="$WORK/e2e-runbook-bad-profile"
if CODEXDOCK_REPORT_DIR="$BAD_PROFILE_RUNBOOK_DIR" \
  CODEXDOCK_HOST=100.64.0.2 \
  CODEXDOCK_USER=manoj \
  CODEXDOCK_WORKSPACE="   " \
  CODEXDOCK_SESSION="bad session" \
  CODEXDOCK_AGENT="   " \
  CODEXDOCK_PROMPT="   " \
  "$ROOT/scripts/e2e-remote.sh" --write-runbook >"$WORK/e2e-runbook-bad-profile.out" 2>&1; then
  echo "expected remote E2E runbook generation to reject invalid profile inputs" >&2
  exit 1
fi
grep -F "CODEXDOCK_WORKSPACE cannot be blank" "$WORK/e2e-runbook-bad-profile.out" >/dev/null
grep -F "CODEXDOCK_SESSION must contain only letters, numbers, underscores, or hyphens" "$WORK/e2e-runbook-bad-profile.out" >/dev/null
grep -F "CODEXDOCK_AGENT cannot be blank" "$WORK/e2e-runbook-bad-profile.out" >/dev/null
grep -F "CODEXDOCK_PROMPT cannot be blank" "$WORK/e2e-runbook-bad-profile.out" >/dev/null
test ! -e "$BAD_PROFILE_RUNBOOK_DIR/context.txt"
test ! -e "$BAD_PROFILE_RUNBOOK_DIR/wsl-prepare.sh"

BAD_KEY_RUNBOOK_DIR="$WORK/e2e-runbook-bad-key-file"
if CODEXDOCK_REPORT_DIR="$BAD_KEY_RUNBOOK_DIR" \
  CODEXDOCK_HOST=100.64.0.2 \
  CODEXDOCK_USER=manoj \
  CODEXDOCK_SSH_AUTHORIZED_KEY_FILE="$WORK/missing.pub" \
  "$ROOT/scripts/e2e-remote.sh" --write-runbook >"$WORK/e2e-runbook-bad-key-file.out" 2>&1; then
  echo "expected remote E2E runbook generation to reject missing SSH authorized key file" >&2
  exit 1
fi
grep -F "CODEXDOCK_SSH_AUTHORIZED_KEY_FILE does not exist: $WORK/missing.pub" "$WORK/e2e-runbook-bad-key-file.out" >/dev/null
test ! -e "$BAD_KEY_RUNBOOK_DIR/context.txt"
test ! -e "$BAD_KEY_RUNBOOK_DIR/wsl-prepare.sh"

BAD_KEY_VALUE_RUNBOOK_DIR="$WORK/e2e-runbook-bad-key-value"
if CODEXDOCK_REPORT_DIR="$BAD_KEY_VALUE_RUNBOOK_DIR" \
  CODEXDOCK_HOST=100.64.0.2 \
  CODEXDOCK_USER=manoj \
  CODEXDOCK_SSH_AUTHORIZED_KEY="   " \
  "$ROOT/scripts/e2e-remote.sh" --write-runbook >"$WORK/e2e-runbook-bad-key-value.out" 2>&1; then
  echo "expected remote E2E runbook generation to reject blank SSH authorized key" >&2
  exit 1
fi
grep -F "CODEXDOCK_SSH_AUTHORIZED_KEY cannot be blank" "$WORK/e2e-runbook-bad-key-value.out" >/dev/null
test ! -e "$BAD_KEY_VALUE_RUNBOOK_DIR/context.txt"
test ! -e "$BAD_KEY_VALUE_RUNBOOK_DIR/wsl-prepare.sh"

BLANK_PUBLIC_KEY_FILE="$WORK/blank.pub"
printf '   \n' >"$BLANK_PUBLIC_KEY_FILE"
BAD_KEY_FILE_EMPTY_RUNBOOK_DIR="$WORK/e2e-runbook-empty-key-file"
if CODEXDOCK_REPORT_DIR="$BAD_KEY_FILE_EMPTY_RUNBOOK_DIR" \
  CODEXDOCK_HOST=100.64.0.2 \
  CODEXDOCK_USER=manoj \
  CODEXDOCK_SSH_AUTHORIZED_KEY_FILE="$BLANK_PUBLIC_KEY_FILE" \
  "$ROOT/scripts/e2e-remote.sh" --write-runbook >"$WORK/e2e-runbook-empty-key-file.out" 2>&1; then
  echo "expected remote E2E runbook generation to reject blank SSH authorized key file content" >&2
  exit 1
fi
grep -F "CODEXDOCK_SSH_AUTHORIZED_KEY_FILE is empty: $BLANK_PUBLIC_KEY_FILE" "$WORK/e2e-runbook-empty-key-file.out" >/dev/null
test ! -e "$BAD_KEY_FILE_EMPTY_RUNBOOK_DIR/context.txt"
test ! -e "$BAD_KEY_FILE_EMPTY_RUNBOOK_DIR/wsl-prepare.sh"

ARM_RUNBOOK_DIR="$WORK/e2e-runbook-arm64"
CODEXDOCK_REPORT_DIR="$ARM_RUNBOOK_DIR" \
  CODEXDOCK_HOST=100.64.0.2 \
  CODEXDOCK_USER=manoj \
  CODEXDOCK_TARGET_ARCH=arm64 \
  "$ROOT/scripts/e2e-remote.sh" --write-runbook >"$WORK/e2e-runbook-arm64.out"
grep -F "remote e2e runbook written" "$WORK/e2e-runbook-arm64.out" >/dev/null
sh -n "$ARM_RUNBOOK_DIR/mac-stage-wsl-codexdock.sh"
grep -F "CODEXDOCK_TARGET_ARCH='arm64'" "$ARM_RUNBOOK_DIR/mac-preflight.sh" >/dev/null
grep -F "CODEXDOCK_TARGET_ARCH='arm64'" "$ARM_RUNBOOK_DIR/mac-run.sh" >/dev/null
grep -F "GOARCH='arm64'" "$ARM_RUNBOOK_DIR/mac-stage-wsl-codexdock.sh" >/dev/null
grep -F "OUT='$ARM_RUNBOOK_DIR/codexdock-linux-arm64'" "$ARM_RUNBOOK_DIR/mac-stage-wsl-codexdock.sh" >/dev/null
grep -F "target_arch=arm64" "$ARM_RUNBOOK_DIR/context.txt" >/dev/null
grep -F "target architecture: arm64" "$ARM_RUNBOOK_DIR/runbook.txt" >/dev/null

BAD_ARCH_RUNBOOK_DIR="$WORK/e2e-runbook-bad-arch"
if CODEXDOCK_REPORT_DIR="$BAD_ARCH_RUNBOOK_DIR" \
  CODEXDOCK_HOST=100.64.0.2 \
  CODEXDOCK_USER=manoj \
  CODEXDOCK_TARGET_ARCH=mips \
  "$ROOT/scripts/e2e-remote.sh" --write-runbook >"$WORK/e2e-runbook-bad-arch.out" 2>&1; then
  echo "expected remote E2E runbook generation to reject unsupported target architecture" >&2
  exit 1
fi
grep -F "unsupported CODEXDOCK_TARGET_ARCH: mips" "$WORK/e2e-runbook-bad-arch.out" >/dev/null
test ! -e "$BAD_ARCH_RUNBOOK_DIR/mac-stage-wsl-codexdock.sh"

BAD_PORT_RUNBOOK_DIR="$WORK/e2e-runbook-bad-port"
if CODEXDOCK_REPORT_DIR="$BAD_PORT_RUNBOOK_DIR" \
  CODEXDOCK_HOST=100.64.0.2 \
  CODEXDOCK_USER=manoj \
  CODEXDOCK_SSH_PORT=not-a-port \
  "$ROOT/scripts/e2e-remote.sh" --write-runbook >"$WORK/e2e-runbook-bad-port.out" 2>&1; then
  echo "expected remote E2E runbook generation to reject invalid SSH port" >&2
  exit 1
fi
grep -F "CODEXDOCK_SSH_PORT must be a positive integer: not-a-port" "$WORK/e2e-runbook-bad-port.out" >/dev/null
test ! -e "$BAD_PORT_RUNBOOK_DIR/mac-run.sh"

BAD_LOG_LINES_RUNBOOK_DIR="$WORK/e2e-runbook-bad-log-lines"
if CODEXDOCK_REPORT_DIR="$BAD_LOG_LINES_RUNBOOK_DIR" \
  CODEXDOCK_HOST=100.64.0.2 \
  CODEXDOCK_USER=manoj \
  CODEXDOCK_LOG_LINES=zero \
  "$ROOT/scripts/e2e-remote.sh" --write-runbook >"$WORK/e2e-runbook-bad-log-lines.out" 2>&1; then
  echo "expected remote E2E runbook generation to reject invalid log line count" >&2
  exit 1
fi
grep -F "CODEXDOCK_LOG_LINES must be a positive integer: zero" "$WORK/e2e-runbook-bad-log-lines.out" >/dev/null
test ! -e "$BAD_LOG_LINES_RUNBOOK_DIR/mac-run.sh"

BAD_RUNBOOK_DIR="$WORK/e2e-runbook-missing"
if CODEXDOCK_REPORT_DIR="$BAD_RUNBOOK_DIR" "$ROOT/scripts/e2e-remote.sh" --write-runbook >"$WORK/e2e-runbook-missing.out" 2>&1; then
  echo "expected remote E2E runbook generation to require target host and user" >&2
  exit 1
fi
grep -F "CODEXDOCK_HOST is required" "$WORK/e2e-runbook-missing.out" >/dev/null
test ! -e "$BAD_RUNBOOK_DIR/mac-run.sh"

NO_SCP_BIN="$WORK/no-scp-bin"
mkdir -p "$NO_SCP_BIN"
for tool in cat dirname go mkdir sed sh; do
  ln -s "$(command -v "$tool")" "$NO_SCP_BIN/$tool"
done
cat >"$NO_SCP_BIN/ssh" <<'EOF'
#!/usr/bin/env sh
exit 0
EOF
chmod +x "$NO_SCP_BIN/ssh"
SCP_PREFLIGHT_REPORT="$WORK/e2e-preflight-require-scp"
if CODEXDOCK_REPORT_DIR="$SCP_PREFLIGHT_REPORT" \
  CODEXDOCK_HOST=100.64.0.2 \
  CODEXDOCK_USER=manoj \
  CODEXDOCK_REQUIRE_SCP=1 \
  PATH="$NO_SCP_BIN" \
  "$ROOT/scripts/e2e-remote.sh" --preflight >"$WORK/e2e-preflight-require-scp.out" 2>&1; then
  echo "expected remote E2E preflight to fail when scp is required but unavailable" >&2
  exit 1
fi
grep -F "remote e2e preflight failed" "$WORK/e2e-preflight-require-scp.out" >/dev/null
grep -F "missing=scp" "$SCP_PREFLIGHT_REPORT/preflight.txt" >/dev/null
grep -F "local_scp=no" "$SCP_PREFLIGHT_REPORT/preflight.txt" >/dev/null
grep -F "scp_required=yes" "$SCP_PREFLIGHT_REPORT/preflight.txt" >/dev/null

NO_GO_BIN="$WORK/no-go-bin"
mkdir -p "$NO_GO_BIN"
for tool in cat dirname mkdir scp sed sh ssh; do
  ln -s "$(command -v "$tool")" "$NO_GO_BIN/$tool"
done
GO_PREFLIGHT_REPORT="$WORK/e2e-preflight-missing-go"
if CODEXDOCK_REPORT_DIR="$GO_PREFLIGHT_REPORT" \
  CODEXDOCK_HOST=100.64.0.2 \
  CODEXDOCK_USER=manoj \
  PATH="$NO_GO_BIN" \
  "$ROOT/scripts/e2e-remote.sh" --preflight >"$WORK/e2e-preflight-missing-go.out" 2>&1; then
  echo "expected remote E2E preflight to fail when go is unavailable" >&2
  exit 1
fi
grep -F "remote e2e preflight failed" "$WORK/e2e-preflight-missing-go.out" >/dev/null
grep -F "missing=go" "$GO_PREFLIGHT_REPORT/preflight.txt" >/dev/null
grep -F "local_go=no" "$GO_PREFLIGHT_REPORT/preflight.txt" >/dev/null
grep -F "local_ssh=yes" "$GO_PREFLIGHT_REPORT/preflight.txt" >/dev/null

BIN_PREFLIGHT_REPORT="$WORK/e2e-preflight-bin-no-go"
if ! CODEXDOCK_REPORT_DIR="$BIN_PREFLIGHT_REPORT" \
  CODEXDOCK_HOST=100.64.0.2 \
  CODEXDOCK_USER=manoj \
  CODEXDOCK_BIN="$BIN" \
  PATH="$NO_GO_BIN" \
  "$ROOT/scripts/e2e-remote.sh" --preflight >"$WORK/e2e-preflight-bin-no-go.out" 2>&1; then
  echo "expected remote E2E preflight to pass without go when CODEXDOCK_BIN is executable" >&2
  exit 1
fi
grep -F "remote e2e preflight ok" "$WORK/e2e-preflight-bin-no-go.out" >/dev/null
grep -F "missing=none" "$BIN_PREFLIGHT_REPORT/preflight.txt" >/dev/null
grep -F "local_go=no" "$BIN_PREFLIGHT_REPORT/preflight.txt" >/dev/null
grep -F "local_codexdock_bin=executable" "$BIN_PREFLIGHT_REPORT/preflight.txt" >/dev/null

BAD_PORT_PREFLIGHT_REPORT="$WORK/e2e-preflight-bad-port"
if CODEXDOCK_REPORT_DIR="$BAD_PORT_PREFLIGHT_REPORT" \
  CODEXDOCK_HOST=100.64.0.2 \
  CODEXDOCK_USER=manoj \
  CODEXDOCK_SSH_PORT=not-a-port \
  "$ROOT/scripts/e2e-remote.sh" --preflight >"$WORK/e2e-preflight-bad-port.out" 2>&1; then
  echo "expected remote E2E preflight to fail when SSH port is invalid" >&2
  exit 1
fi
grep -F "remote e2e preflight failed" "$WORK/e2e-preflight-bad-port.out" >/dev/null
grep -F "invalid=CODEXDOCK_SSH_PORT must be a positive integer" "$BAD_PORT_PREFLIGHT_REPORT/preflight.txt" >/dev/null
grep -F "ssh_port=not-a-port" "$BAD_PORT_PREFLIGHT_REPORT/context.txt" >/dev/null

BAD_LOG_LINES_PREFLIGHT_REPORT="$WORK/e2e-preflight-bad-log-lines"
if CODEXDOCK_REPORT_DIR="$BAD_LOG_LINES_PREFLIGHT_REPORT" \
  CODEXDOCK_HOST=100.64.0.2 \
  CODEXDOCK_USER=manoj \
  CODEXDOCK_LOG_LINES=zero \
  "$ROOT/scripts/e2e-remote.sh" --preflight >"$WORK/e2e-preflight-bad-log-lines.out" 2>&1; then
  echo "expected remote E2E preflight to fail when log line count is invalid" >&2
  exit 1
fi
grep -F "remote e2e preflight failed" "$WORK/e2e-preflight-bad-log-lines.out" >/dev/null
grep -F "invalid=CODEXDOCK_LOG_LINES must be a positive integer" "$BAD_LOG_LINES_PREFLIGHT_REPORT/preflight.txt" >/dev/null
grep -F "log_lines=zero" "$BAD_LOG_LINES_PREFLIGHT_REPORT/context.txt" >/dev/null

BAD_ARCH_PREFLIGHT_REPORT="$WORK/e2e-preflight-bad-arch"
if CODEXDOCK_REPORT_DIR="$BAD_ARCH_PREFLIGHT_REPORT" \
  CODEXDOCK_HOST=100.64.0.2 \
  CODEXDOCK_USER=manoj \
  CODEXDOCK_TARGET_ARCH=mips \
  "$ROOT/scripts/e2e-remote.sh" --preflight >"$WORK/e2e-preflight-bad-arch.out" 2>&1; then
  echo "expected remote E2E preflight to fail when target architecture is unsupported" >&2
  exit 1
fi
grep -F "remote e2e preflight failed" "$WORK/e2e-preflight-bad-arch.out" >/dev/null
grep -F "invalid=unsupported CODEXDOCK_TARGET_ARCH: mips" "$BAD_ARCH_PREFLIGHT_REPORT/preflight.txt" >/dev/null
grep -F "target_arch=mips" "$BAD_ARCH_PREFLIGHT_REPORT/context.txt" >/dev/null

MULTI_INVALID_PREFLIGHT_REPORT="$WORK/e2e-preflight-multiple-invalid"
if CODEXDOCK_REPORT_DIR="$MULTI_INVALID_PREFLIGHT_REPORT" \
  CODEXDOCK_HOST=100.64.0.2 \
  CODEXDOCK_USER=manoj \
  CODEXDOCK_SSH_PORT=not-a-port \
  CODEXDOCK_LOG_LINES=zero \
  CODEXDOCK_TARGET_ARCH=mips \
  CODEXDOCK_SSH_AUTHORIZED_KEY=inline-key \
  CODEXDOCK_SSH_AUTHORIZED_KEY_FILE="$PUBLIC_KEY_FILE" \
  "$ROOT/scripts/e2e-remote.sh" --preflight >"$WORK/e2e-preflight-multiple-invalid.out" 2>&1; then
  echo "expected remote E2E preflight to report multiple invalid inputs" >&2
  exit 1
fi
grep -F "remote e2e preflight failed" "$WORK/e2e-preflight-multiple-invalid.out" >/dev/null
grep -F "invalid=CODEXDOCK_SSH_PORT must be a positive integer" "$MULTI_INVALID_PREFLIGHT_REPORT/preflight.txt" >/dev/null
grep -F "CODEXDOCK_LOG_LINES must be a positive integer" "$MULTI_INVALID_PREFLIGHT_REPORT/preflight.txt" >/dev/null
grep -F "unsupported CODEXDOCK_TARGET_ARCH: mips" "$MULTI_INVALID_PREFLIGHT_REPORT/preflight.txt" >/dev/null
grep -F "set either CODEXDOCK_SSH_AUTHORIZED_KEY or CODEXDOCK_SSH_AUTHORIZED_KEY_FILE, not both" "$MULTI_INVALID_PREFLIGHT_REPORT/preflight.txt" >/dev/null

BAD_KEY_VALUE_PREFLIGHT_REPORT="$WORK/e2e-preflight-bad-key-value"
if CODEXDOCK_REPORT_DIR="$BAD_KEY_VALUE_PREFLIGHT_REPORT" \
  CODEXDOCK_HOST=100.64.0.2 \
  CODEXDOCK_USER=manoj \
  CODEXDOCK_SSH_AUTHORIZED_KEY="   " \
  "$ROOT/scripts/e2e-remote.sh" --preflight >"$WORK/e2e-preflight-bad-key-value.out" 2>&1; then
  echo "expected remote E2E preflight to reject blank SSH authorized key" >&2
  exit 1
fi
grep -F "remote e2e preflight failed" "$WORK/e2e-preflight-bad-key-value.out" >/dev/null
grep -F "CODEXDOCK_SSH_AUTHORIZED_KEY cannot be blank" "$BAD_KEY_VALUE_PREFLIGHT_REPORT/preflight.txt" >/dev/null
grep -F "ssh_authorized_key_set=yes" "$BAD_KEY_VALUE_PREFLIGHT_REPORT/context.txt" >/dev/null

BAD_KEY_FILE_EMPTY_PREFLIGHT_REPORT="$WORK/e2e-preflight-empty-key-file"
if CODEXDOCK_REPORT_DIR="$BAD_KEY_FILE_EMPTY_PREFLIGHT_REPORT" \
  CODEXDOCK_HOST=100.64.0.2 \
  CODEXDOCK_USER=manoj \
  CODEXDOCK_SSH_AUTHORIZED_KEY_FILE="$BLANK_PUBLIC_KEY_FILE" \
  "$ROOT/scripts/e2e-remote.sh" --preflight >"$WORK/e2e-preflight-empty-key-file.out" 2>&1; then
  echo "expected remote E2E preflight to reject blank SSH authorized key file content" >&2
  exit 1
fi
grep -F "remote e2e preflight failed" "$WORK/e2e-preflight-empty-key-file.out" >/dev/null
grep -F "CODEXDOCK_SSH_AUTHORIZED_KEY_FILE is empty" "$BAD_KEY_FILE_EMPTY_PREFLIGHT_REPORT/preflight.txt" >/dev/null
grep -F "ssh_authorized_key_file=empty" "$BAD_KEY_FILE_EMPTY_PREFLIGHT_REPORT/preflight.txt" >/dev/null

BAD_FLAGS_PREFLIGHT_REPORT="$WORK/e2e-preflight-bad-flags"
if CODEXDOCK_REPORT_DIR="$BAD_FLAGS_PREFLIGHT_REPORT" \
  CODEXDOCK_HOST=100.64.0.2 \
  CODEXDOCK_USER=manoj \
  CODEXDOCK_ADOPT=maybe \
  CODEXDOCK_PREPARE=later \
  CODEXDOCK_REQUIRE_SCP=required \
  "$ROOT/scripts/e2e-remote.sh" --preflight >"$WORK/e2e-preflight-bad-flags.out" 2>&1; then
  echo "expected remote E2E preflight to reject invalid flag values" >&2
  exit 1
fi
grep -F "remote e2e preflight failed" "$WORK/e2e-preflight-bad-flags.out" >/dev/null
grep -F "CODEXDOCK_ADOPT must be 0 or 1" "$BAD_FLAGS_PREFLIGHT_REPORT/preflight.txt" >/dev/null
grep -F "CODEXDOCK_PREPARE must be 0 or 1" "$BAD_FLAGS_PREFLIGHT_REPORT/preflight.txt" >/dev/null
grep -F "CODEXDOCK_REQUIRE_SCP must be 0 or 1" "$BAD_FLAGS_PREFLIGHT_REPORT/preflight.txt" >/dev/null
grep -F "adopt=maybe" "$BAD_FLAGS_PREFLIGHT_REPORT/context.txt" >/dev/null
grep -F "prepare=later" "$BAD_FLAGS_PREFLIGHT_REPORT/context.txt" >/dev/null

BAD_CONTROL_URL_PREFLIGHT_REPORT="$WORK/e2e-preflight-bad-control-url"
if CODEXDOCK_REPORT_DIR="$BAD_CONTROL_URL_PREFLIGHT_REPORT" \
  CODEXDOCK_HOST=100.64.0.2 \
  CODEXDOCK_USER=manoj \
  CODEXDOCK_CONTROL_URL="   " \
  "$ROOT/scripts/e2e-remote.sh" --preflight >"$WORK/e2e-preflight-bad-control-url.out" 2>&1; then
  echo "expected remote E2E preflight to reject blank control URL" >&2
  exit 1
fi
grep -F "remote e2e preflight failed" "$WORK/e2e-preflight-bad-control-url.out" >/dev/null
grep -F "CODEXDOCK_CONTROL_URL cannot be blank" "$BAD_CONTROL_URL_PREFLIGHT_REPORT/preflight.txt" >/dev/null
grep -Fx "control_url=" "$BAD_CONTROL_URL_PREFLIGHT_REPORT/context.txt" >/dev/null

BAD_TARGET_PREFLIGHT_REPORT="$WORK/e2e-preflight-bad-target"
if CODEXDOCK_REPORT_DIR="$BAD_TARGET_PREFLIGHT_REPORT" \
  CODEXDOCK_HOST="   " \
  CODEXDOCK_USER="   " \
  "$ROOT/scripts/e2e-remote.sh" --preflight >"$WORK/e2e-preflight-bad-target.out" 2>&1; then
  echo "expected remote E2E preflight to reject blank target inputs" >&2
  exit 1
fi
grep -F "remote e2e preflight failed" "$WORK/e2e-preflight-bad-target.out" >/dev/null
grep -F "CODEXDOCK_HOST cannot be blank" "$BAD_TARGET_PREFLIGHT_REPORT/preflight.txt" >/dev/null
grep -F "CODEXDOCK_USER cannot be blank" "$BAD_TARGET_PREFLIGHT_REPORT/preflight.txt" >/dev/null
grep -Fx "host=" "$BAD_TARGET_PREFLIGHT_REPORT/context.txt" >/dev/null
grep -Fx "ssh_user=" "$BAD_TARGET_PREFLIGHT_REPORT/context.txt" >/dev/null

BAD_PROFILE_PREFLIGHT_REPORT="$WORK/e2e-preflight-bad-profile"
if CODEXDOCK_REPORT_DIR="$BAD_PROFILE_PREFLIGHT_REPORT" \
  CODEXDOCK_HOST=100.64.0.2 \
  CODEXDOCK_USER=manoj \
  CODEXDOCK_WORKSPACE="   " \
  CODEXDOCK_SESSION="bad session" \
  CODEXDOCK_AGENT="   " \
  CODEXDOCK_PROMPT="   " \
  "$ROOT/scripts/e2e-remote.sh" --preflight >"$WORK/e2e-preflight-bad-profile.out" 2>&1; then
  echo "expected remote E2E preflight to reject invalid profile inputs" >&2
  exit 1
fi
grep -F "remote e2e preflight failed" "$WORK/e2e-preflight-bad-profile.out" >/dev/null
grep -F "CODEXDOCK_WORKSPACE cannot be blank" "$BAD_PROFILE_PREFLIGHT_REPORT/preflight.txt" >/dev/null
grep -F "CODEXDOCK_SESSION must contain only letters, numbers, underscores, or hyphens" "$BAD_PROFILE_PREFLIGHT_REPORT/preflight.txt" >/dev/null
grep -F "CODEXDOCK_AGENT cannot be blank" "$BAD_PROFILE_PREFLIGHT_REPORT/preflight.txt" >/dev/null
grep -F "CODEXDOCK_PROMPT cannot be blank" "$BAD_PROFILE_PREFLIGHT_REPORT/preflight.txt" >/dev/null
grep -Fx "workspace=" "$BAD_PROFILE_PREFLIGHT_REPORT/context.txt" >/dev/null
grep -F "session=bad session" "$BAD_PROFILE_PREFLIGHT_REPORT/context.txt" >/dev/null
grep -Fx "agent=" "$BAD_PROFILE_PREFLIGHT_REPORT/context.txt" >/dev/null
grep -Fx "prompt=" "$BAD_PROFILE_PREFLIGHT_REPORT/context.txt" >/dev/null

PREFLIGHT_REPORT="$WORK/e2e-preflight-report"
if CODEXDOCK_REPORT_DIR="$PREFLIGHT_REPORT" "$ROOT/scripts/e2e-remote.sh" --preflight >"$WORK/e2e-preflight.out" 2>&1; then
  echo "expected remote E2E preflight to fail without CODEXDOCK_HOST and CODEXDOCK_USER" >&2
  exit 1
fi
grep -F "remote e2e preflight failed" "$WORK/e2e-preflight.out" >/dev/null
grep -F "report directory: $PREFLIGHT_REPORT" "$WORK/e2e-preflight.out" >/dev/null
test -f "$PREFLIGHT_REPORT/preflight.txt"
test -f "$PREFLIGHT_REPORT/result.txt"
grep -F "missing=CODEXDOCK_HOST CODEXDOCK_USER" "$PREFLIGHT_REPORT/preflight.txt" >/dev/null
grep -F "local_ssh=yes" "$PREFLIGHT_REPORT/preflight.txt" >/dev/null
grep -F "status=failure" "$PREFLIGHT_REPORT/result.txt" >/dev/null
grep -F "exit_code=2" "$PREFLIGHT_REPORT/result.txt" >/dev/null
grep -F "preflight=failed" "$PREFLIGHT_REPORT/result.txt" >/dev/null

FAKE_BIN="$WORK/bin"
FAKE_CURL_LOG="$WORK/fake-curl.log"
FAKE_CURL_BODY="$WORK/fake-curl-body.json"
FAKE_CURL_PAYLOADS="$WORK/fake-curl-payloads.jsonl"
mkdir -p "$FAKE_BIN"
cat >"$FAKE_BIN/curl" <<'EOF'
#!/usr/bin/env sh
set -eu
printf 'curl %s\n' "$*" >>"$CODEXDOCK_FAKE_CURL_LOG"
BODY=$(mktemp "${TMPDIR:-/tmp}/codexdock-fake-curl-body.XXXXXX")
cleanup() {
  rm -f "$BODY"
}
trap cleanup EXIT INT TERM
url=
while [ "$#" -gt 0 ]; do
  case "$1" in
    http://*|https://*) url=$1 ;;
  esac
  if [ "$1" = "--data-binary" ]; then
    shift
    if [ "${1:-}" = "@-" ]; then
      cat >"$BODY"
      cp "$BODY" "$CODEXDOCK_FAKE_CURL_BODY"
      if [ -n "${CODEXDOCK_FAKE_CURL_PAYLOADS:-}" ]; then
        jq -c . "$BODY" >>"$CODEXDOCK_FAKE_CURL_PAYLOADS"
      fi
    fi
  fi
  shift
done
title=
if [ -s "$BODY" ]; then
  title=$(jq -r '.values.Title // .name // empty' "$BODY" 2>/dev/null || printf '')
fi
case "$url" in
  */auth/signup)
    jq -n -c '{accessToken:"tenant-token"}'
    ;;
  */auth/personal-access-tokens)
    jq -n -c '{accessToken:"cdock-pat-token"}'
    ;;
  */data/CodexDock/Project)
    jq -n -c --arg name "${title:-CodexDock}" '{id:111764,name:$name}'
    ;;
  */data/CodexDock/RoadmapItem)
    case "$title" in
      "Product model and command UX") id=111765 ;;
      "TrentPlatform project system of record") id=111766 ;;
      "CLI skeleton, local config, and first-time init") id=111767 ;;
      "Managed OSS component integration") id=111768 ;;
      "Machine registration and discovery") id=111769 ;;
      "SSH connect workflow") id=111770 ;;
      "Codex tmux workflow") id=111771 ;;
      "Hardening, packaging, and smoke checks") id=111772 ;;
      "Physical Mac-to-WSL E2E validation") id=111773 ;;
      *) id=111799 ;;
    esac
    jq -n -c --argjson id "$id" --arg name "$title" '{id:$id,name:$name}'
    ;;
  */data/CodexDock/Artifact)
    printf '{"id":12345,"name":"Remote E2E Report: homepc success"}\n'
    ;;
  *)
    printf '{"id":9000,"name":"metadata"}\n'
    ;;
esac
EOF
chmod +x "$FAKE_BIN/curl"

: >"$FAKE_CURL_LOG"
: >"$FAKE_CURL_PAYLOADS"
TRENT_BOOTSTRAP_ENV="$WORK/trent-bootstrap.env"
CODEXDOCK_FAKE_CURL_LOG="$FAKE_CURL_LOG" \
  CODEXDOCK_FAKE_CURL_BODY="$FAKE_CURL_BODY" \
  CODEXDOCK_FAKE_CURL_PAYLOADS="$FAKE_CURL_PAYLOADS" \
  CODEXDOCK_TRENT_TOKEN=test-token \
  CODEXDOCK_TRENT_BASE_URL=https://trent.example \
  CODEXDOCK_TRENT_ENV_FILE="$TRENT_BOOTSTRAP_ENV" \
  PATH="$FAKE_BIN:$PATH" \
  "$ROOT/scripts/trent-bootstrap.sh" >"$WORK/trent-bootstrap.out"
grep -F "bootstrapped TrentPlatform CodexDock metadata" "$WORK/trent-bootstrap.out" >/dev/null
grep -F "https://trent.example/api/v1/metadata/namespaces" "$FAKE_CURL_LOG" >/dev/null
grep -F "https://trent.example/api/v1/metadata/namespaces/CodexDock/objects" "$FAKE_CURL_LOG" >/dev/null
grep -F "https://trent.example/api/v1/metadata/namespaces/CodexDock/objects/Project/fields" "$FAKE_CURL_LOG" >/dev/null
grep -F "https://trent.example/api/v1/metadata/namespaces/CodexDock/objects/Artifact/fields" "$FAKE_CURL_LOG" >/dev/null
grep -F "https://trent.example/api/v1/metadata/namespaces/CodexDock/objects/RoadmapItem/fields" "$FAKE_CURL_LOG" >/dev/null
grep -F "https://trent.example/api/v1/data/CodexDock/Project" "$FAKE_CURL_LOG" >/dev/null
grep -F "https://trent.example/api/v1/data/CodexDock/RoadmapItem" "$FAKE_CURL_LOG" >/dev/null
grep -F "Authorization: Bearer test-token" "$FAKE_CURL_LOG" >/dev/null
jq -e '.values.Title == "Physical Mac-to-WSL E2E validation"' "$FAKE_CURL_BODY" >/dev/null
jq -e '.values.Status == "pending"' "$FAKE_CURL_BODY" >/dev/null
jq -e '.values.Project == "111764"' "$FAKE_CURL_BODY" >/dev/null
grep -F "CODEXDOCK_TRENT_PROJECT=111764" "$WORK/trent-bootstrap.out" >/dev/null
grep -F "CODEXDOCK_TRENT_ROADMAP_IDS='111765 111766 111767 111768 111769 111770 111771 111772 111773'" "$WORK/trent-bootstrap.out" >/dev/null
jq -e '(.picklistValues // [] | map(.value)) as $values | select(.name == "ArtifactType" and .fieldType == "picklist" and ($values | index("plan")) and ($values | index("repository")))' "$FAKE_CURL_PAYLOADS" >/dev/null
jq -e '(.picklistValues // [] | map(.value)) as $values | select(.name == "Status" and .fieldType == "picklist" and ($values | index("pending")) and ($values | index("active")) and ($values | index("done")))' "$FAKE_CURL_PAYLOADS" >/dev/null
jq -e 'select(.values.Title == "GitHub repository" and .values.ArtifactType == "repository" and .values.Status == "active" and .values.Project == "111764" and (.values.Content | contains("https://github.com/edisontrent17/codexdock")))' "$FAKE_CURL_PAYLOADS" >/dev/null
jq -e 'select(.name == "Content" and .fieldType == "text")' "$FAKE_CURL_PAYLOADS" >/dev/null
jq -e 'select(.name == "Scope" and .fieldType == "text")' "$FAKE_CURL_PAYLOADS" >/dev/null
jq -e 'select(.name == "Content" and .fieldType == "text" and .textLength == 65535)' "$FAKE_CURL_PAYLOADS" >/dev/null
jq -e 'select(.name == "Scope" and .fieldType == "text" and .textLength == 4096)' "$FAKE_CURL_PAYLOADS" >/dev/null
grep -F "CODEXDOCK_TRENT_PROJECT=111764" "$TRENT_BOOTSTRAP_ENV" >/dev/null
grep -F "CODEXDOCK_TRENT_ROADMAP_IDS='111765 111766 111767 111768 111769 111770 111771 111772 111773'" "$TRENT_BOOTSTRAP_ENV" >/dev/null
"$ROOT/scripts/trent-record-e2e.sh" --help >"$WORK/trent-record-help.out"
grep -F "CODEXDOCK_TRENT_ENV_FILE" "$WORK/trent-record-help.out" >/dev/null
"$ROOT/scripts/trent-close-roadmap.sh" --help >"$WORK/trent-close-help.out"
grep -F "CODEXDOCK_TRENT_ENV_FILE" "$WORK/trent-close-help.out" >/dev/null
"$ROOT/scripts/trent-finalize-e2e.sh" --help >"$WORK/trent-finalize-help.out"
grep -F "CODEXDOCK_TRENT_ENV_FILE" "$WORK/trent-finalize-help.out" >/dev/null
"$ROOT/scripts/trent-provision-org.sh" --help >"$WORK/trent-provision-help.out"
grep -F "CODEXDOCK_TRENT_ORG_NAME" "$WORK/trent-provision-help.out" >/dev/null
grep -F "CODEXDOCK_TRENT_ADMIN_PASSWORD" "$WORK/trent-provision-help.out" >/dev/null

TRENT_PROVISION_TOKEN_FILE="$WORK/trent-provision-token.json"
TRENT_PROVISION_ENV="$WORK/trent-provision.env"
: >"$FAKE_CURL_LOG"
: >"$FAKE_CURL_PAYLOADS"
CODEXDOCK_FAKE_CURL_LOG="$FAKE_CURL_LOG" \
  CODEXDOCK_FAKE_CURL_BODY="$FAKE_CURL_BODY" \
  CODEXDOCK_FAKE_CURL_PAYLOADS="$FAKE_CURL_PAYLOADS" \
  CODEXDOCK_TRENT_BASE_URL=https://trent.example \
  CODEXDOCK_TRENT_ORG_NAME=CodexDockSmoke \
  CODEXDOCK_TRENT_ORG_LABEL="CodexDock Smoke" \
  CODEXDOCK_TRENT_ADMIN_EMAIL=admin@codexdock.example \
  CODEXDOCK_TRENT_ADMIN_PASSWORD=ChangeMe12345 \
  CODEXDOCK_TRENT_ADMIN_DISPLAY_NAME="CodexDock Admin" \
  CODEXDOCK_TRENT_TOKEN_FILE="$TRENT_PROVISION_TOKEN_FILE" \
  CODEXDOCK_TRENT_ENV_FILE="$TRENT_PROVISION_ENV" \
  PATH="$FAKE_BIN:$PATH" \
  "$ROOT/scripts/trent-provision-org.sh" >"$WORK/trent-provision.out"
grep -F "provisioned TrentPlatform org CodexDockSmoke" "$WORK/trent-provision.out" >/dev/null
grep -F "wrote TrentPlatform token file: $TRENT_PROVISION_TOKEN_FILE" "$WORK/trent-provision.out" >/dev/null
grep -F "wrote TrentPlatform env file: $TRENT_PROVISION_ENV" "$WORK/trent-provision.out" >/dev/null
grep -F "https://trent.example/api/v1/auth/signup" "$FAKE_CURL_LOG" >/dev/null
grep -F "https://trent.example/api/v1/auth/personal-access-tokens" "$FAKE_CURL_LOG" >/dev/null
grep -F "Authorization: Bearer tenant-token" "$FAKE_CURL_LOG" >/dev/null
grep -F "Authorization: Bearer cdock-pat-token" "$FAKE_CURL_LOG" >/dev/null
jq -e '.personalAccessToken == "cdock-pat-token"' "$TRENT_PROVISION_TOKEN_FILE" >/dev/null
jq -e '.orgName == "CodexDockSmoke"' "$TRENT_PROVISION_TOKEN_FILE" >/dev/null
jq -e '.adminEmail == "admin@codexdock.example"' "$TRENT_PROVISION_TOKEN_FILE" >/dev/null
jq -e '.scopes == ["metadata:read","metadata:write","data:read","data:write","query:execute"]' "$TRENT_PROVISION_TOKEN_FILE" >/dev/null
grep -F "CODEXDOCK_TRENT_PROJECT=111764" "$TRENT_PROVISION_ENV" >/dev/null
jq -e 'select(.orgName == "CodexDockSmoke" and .adminEmail == "admin@codexdock.example")' "$FAKE_CURL_PAYLOADS" >/dev/null
jq -e 'select(.name == "CodexDock Agent" and (.scopes | join(",") == "metadata:read,metadata:write,data:read,data:write,query:execute"))' "$FAKE_CURL_PAYLOADS" >/dev/null

BAD_TRENT_PROVISION_TOKEN_FILE="$WORK/bad-trent-provision-token.json"
BAD_TRENT_PROVISION_ENV="$WORK/bad-trent-provision.env"
: >"$FAKE_CURL_LOG"
if CODEXDOCK_FAKE_CURL_LOG="$FAKE_CURL_LOG" \
  CODEXDOCK_FAKE_CURL_BODY="$FAKE_CURL_BODY" \
  CODEXDOCK_TRENT_BASE_URL=https://trent.example \
  CODEXDOCK_TRENT_ORG_NAME=Bad_Org \
  CODEXDOCK_TRENT_ADMIN_EMAIL=admin@codexdock.example \
  CODEXDOCK_TRENT_ADMIN_PASSWORD=ChangeMe12345 \
  CODEXDOCK_TRENT_TOKEN_FILE="$BAD_TRENT_PROVISION_TOKEN_FILE" \
  CODEXDOCK_TRENT_ENV_FILE="$BAD_TRENT_PROVISION_ENV" \
  PATH="$FAKE_BIN:$PATH" \
  "$ROOT/scripts/trent-provision-org.sh" >"$WORK/trent-provision-bad-org.out" 2>&1; then
  echo "expected TrentPlatform org provisioning to reject invalid org names before signup" >&2
  exit 1
fi
grep -F "CODEXDOCK_TRENT_ORG_NAME must start with a letter and contain only letters and numbers" "$WORK/trent-provision-bad-org.out" >/dev/null
test ! -s "$FAKE_CURL_LOG"
test ! -e "$BAD_TRENT_PROVISION_TOKEN_FILE"
test ! -e "$BAD_TRENT_PROVISION_ENV"

TRENT_REPORT="$WORK/trent-report"
mkdir -p "$TRENT_REPORT"
cat >"$TRENT_REPORT/result.txt" <<'EOF'
status=success
exit_code=0
network=personal
machine=homepc
session=codexdock-e2e
session_started=yes
session_stopped=yes
cleanup_attempted=no
cleanup_exit_code=not_applicable
EOF
cat >"$TRENT_REPORT/context.txt" <<'EOF'
network=personal
machine=homepc
host=100.64.0.2
control_url=
ssh_user=manoj
ssh_port=22
adopt=0
prepare=1
workspace=~/code
session=codexdock-e2e
agent=codex
prompt=codexdock smoke ping
log_lines=40
ssh_authorized_key_set=no
ssh_authorized_key_file_set=no
require_scp=0
target_arch=amd64
codexdock_bin=
EOF
for step in build init prepare doctor doctor_all start sessions sessions_all send logs stop sessions_after_stop; do
  printf '%s command\n' "$step" >"$TRENT_REPORT/$step.cmd"
  printf '%s output\n' "$step" >"$TRENT_REPORT/$step.out"
  : >"$TRENT_REPORT/$step.err"
done
cat >"$TRENT_REPORT/build.cmd" <<'EOF'
env GOCACHE=/tmp/codexdock-gocache GOMODCACHE=/tmp/codexdock-gomodcache /repo/scripts/build.sh
EOF
cat >"$TRENT_REPORT/init.cmd" <<'EOF'
env HOME=/tmp/codexdock-home /tmp/codexdock init --network personal --machine homepc --host 100.64.0.2 --ssh-user manoj --ssh-port 22 --workspace ~/code --session codexdock-e2e --agent codex
EOF
cat >"$TRENT_REPORT/prepare.cmd" <<'EOF'
env HOME=/tmp/codexdock-home /tmp/codexdock doctor homepc --repair --yes --target-os linux --role codex-host
EOF
cat >"$TRENT_REPORT/doctor.cmd" <<'EOF'
env HOME=/tmp/codexdock-home /tmp/codexdock doctor homepc
EOF
cat >"$TRENT_REPORT/doctor_all.cmd" <<'EOF'
env HOME=/tmp/codexdock-home /tmp/codexdock doctor --all
EOF
cat >"$TRENT_REPORT/start.cmd" <<'EOF'
env HOME=/tmp/codexdock-home /tmp/codexdock start homepc
EOF
cat >"$TRENT_REPORT/sessions.cmd" <<'EOF'
env HOME=/tmp/codexdock-home /tmp/codexdock sessions homepc
EOF
cat >"$TRENT_REPORT/sessions_all.cmd" <<'EOF'
env HOME=/tmp/codexdock-home /tmp/codexdock sessions
EOF
cat >"$TRENT_REPORT/send.cmd" <<'EOF'
env HOME=/tmp/codexdock-home /tmp/codexdock send homepc codexdock smoke ping
EOF
cat >"$TRENT_REPORT/logs.cmd" <<'EOF'
env HOME=/tmp/codexdock-home /tmp/codexdock logs homepc --lines 40
EOF
cat >"$TRENT_REPORT/stop.cmd" <<'EOF'
env HOME=/tmp/codexdock-home /tmp/codexdock stop homepc --force
EOF
cat >"$TRENT_REPORT/sessions_after_stop.cmd" <<'EOF'
env HOME=/tmp/codexdock-home /tmp/codexdock sessions homepc
EOF
cat >"$TRENT_REPORT/doctor.out" <<'EOF'
ok can connect to homepc
ok remote tmux found
ok remote codex found
ok workspace exists
EOF
cat >"$TRENT_REPORT/doctor_all.out" <<'EOF'
ok can connect to homepc
EOF
cat >"$TRENT_REPORT/start.out" <<'EOF'
Started Codex session 'codexdock-e2e' on homepc.
EOF
cat >"$TRENT_REPORT/sessions.out" <<'EOF'
homepc	codexdock-e2e	running
EOF
cat >"$TRENT_REPORT/sessions_all.out" <<'EOF'
homepc	codexdock-e2e	running
EOF
cat >"$TRENT_REPORT/send.out" <<'EOF'
Sent prompt to codexdock-e2e on homepc.
EOF
cat >"$TRENT_REPORT/logs.out" <<'EOF'
codex simulated log
EOF
cat >"$TRENT_REPORT/stop.out" <<'EOF'
Stopped Codex session 'codexdock-e2e' on homepc.
EOF
cat >"$TRENT_REPORT/stop.err" <<'EOF'
warning: Codex session 'codexdock-e2e' on homepc will be killed.
EOF
cat >"$TRENT_REPORT/sessions_after_stop.out" <<'EOF'
No tmux sessions found on homepc.
EOF
BIN_BUILD_REPORT="$WORK/bin-build-report"
cp -R "$TRENT_REPORT" "$BIN_BUILD_REPORT"
sed 's|^codexdock_bin=$|codexdock_bin=/usr/local/bin/codexdock|' "$TRENT_REPORT/context.txt" >"$BIN_BUILD_REPORT/context.txt"
cat >"$BIN_BUILD_REPORT/build.cmd" <<'EOF'
env CODEXDOCK_BIN=/usr/local/bin/codexdock /usr/local/bin/codexdock version
EOF
cat >"$BIN_BUILD_REPORT/build.out" <<'EOF'
codexdock smoke
commit smoke
built 1970-01-01T00:00:00Z
EOF
"$ROOT/scripts/validate-e2e-report.sh" --full "$BIN_BUILD_REPORT" >"$WORK/bin-build-validate.out"
grep -F "remote E2E full report ok" "$WORK/bin-build-validate.out" >/dev/null
BAD_CONTEXT_BIN_FIELD_CLOSE_REPORT="$WORK/bad-context-bin-field-close-report"
cp -R "$TRENT_REPORT" "$BAD_CONTEXT_BIN_FIELD_CLOSE_REPORT"
sed '/^codexdock_bin=/d' "$TRENT_REPORT/context.txt" >"$BAD_CONTEXT_BIN_FIELD_CLOSE_REPORT/context.txt"
if "$ROOT/scripts/validate-e2e-report.sh" --full "$BAD_CONTEXT_BIN_FIELD_CLOSE_REPORT" >"$WORK/trent-close-bad-context-bin-field.out" 2>&1; then
  echo "expected remote E2E validator to reject reports without codexdock_bin context" >&2
  exit 1
fi
grep -F "remote E2E report artifact did not contain expected text: context.txt" "$WORK/trent-close-bad-context-bin-field.out" >/dev/null

BAD_BIN_CONTEXT_REPORT="$WORK/bad-bin-context-report"
cp -R "$BIN_BUILD_REPORT" "$BAD_BIN_CONTEXT_REPORT"
sed 's|^codexdock_bin=/usr/local/bin/codexdock$|codexdock_bin=|' "$BIN_BUILD_REPORT/context.txt" >"$BAD_BIN_CONTEXT_REPORT/context.txt"
if "$ROOT/scripts/validate-e2e-report.sh" --full "$BAD_BIN_CONTEXT_REPORT" >"$WORK/bad-bin-context-validate.out" 2>&1; then
  echo "expected remote E2E validator to reject binary build reports without codexdock_bin context value" >&2
  exit 1
fi
grep -F "remote E2E report context codexdock_bin cannot be blank for binary build reports" "$WORK/bad-bin-context-validate.out" >/dev/null
CODEXDOCK_FAKE_CURL_LOG="$FAKE_CURL_LOG" \
  CODEXDOCK_FAKE_CURL_BODY="$FAKE_CURL_BODY" \
  CODEXDOCK_TRENT_TOKEN=test-token \
  CODEXDOCK_TRENT_PROJECT=111764 \
  CODEXDOCK_TRENT_BASE_URL=https://trent.example \
  PATH="$FAKE_BIN:$PATH" \
  "$ROOT/scripts/trent-record-e2e.sh" "$TRENT_REPORT" >"$WORK/trent-record.out"
grep -F '"id":12345' "$WORK/trent-record.out" >/dev/null
grep -F "https://trent.example/api/v1/data/CodexDock/Artifact" "$FAKE_CURL_LOG" >/dev/null
grep -F "Authorization: Bearer test-token" "$FAKE_CURL_LOG" >/dev/null
jq -e '.name == "Remote E2E Report: homepc success"' "$FAKE_CURL_BODY" >/dev/null
jq -e '.values.Title == "Remote E2E Report: homepc success"' "$FAKE_CURL_BODY" >/dev/null
jq -e '.values.ArtifactType == "plan"' "$FAKE_CURL_BODY" >/dev/null
jq -e '.values.Status == "active"' "$FAKE_CURL_BODY" >/dev/null
jq -e '.values.Project == "111764"' "$FAKE_CURL_BODY" >/dev/null
jq -e '.values.Content | contains("status=success")' "$FAKE_CURL_BODY" >/dev/null
jq -e '.values.Content | contains("session_stopped=yes")' "$FAKE_CURL_BODY" >/dev/null
jq -e '.values.Content | contains("command artifacts")' "$FAKE_CURL_BODY" >/dev/null
jq -e '.values.Content | contains("build.cmd: env GOCACHE=/tmp/codexdock-gocache GOMODCACHE=/tmp/codexdock-gomodcache /repo/scripts/build.sh")' "$FAKE_CURL_BODY" >/dev/null
jq -e '.values.Content | contains("init.cmd: env HOME=/tmp/codexdock-home /tmp/codexdock init --network personal --machine homepc")' "$FAKE_CURL_BODY" >/dev/null
jq -e '.values.Content | contains("doctor.out: bytes=")' "$FAKE_CURL_BODY" >/dev/null
jq -e '.values.Content | contains("stop.err: bytes=")' "$FAKE_CURL_BODY" >/dev/null

TRENT_DIRECT_ENV="$WORK/trent-direct.env"
cat >"$TRENT_DIRECT_ENV" <<'EOF'
CODEXDOCK_TRENT_PROJECT=111764
CODEXDOCK_TRENT_ROADMAP_IDS='222001 222002'
EOF
: >"$FAKE_CURL_LOG"
CODEXDOCK_FAKE_CURL_LOG="$FAKE_CURL_LOG" \
  CODEXDOCK_FAKE_CURL_BODY="$FAKE_CURL_BODY" \
  CODEXDOCK_TRENT_TOKEN=test-token \
  CODEXDOCK_TRENT_BASE_URL=https://trent.example \
  CODEXDOCK_TRENT_ENV_FILE="$TRENT_DIRECT_ENV" \
  PATH="$FAKE_BIN:$PATH" \
  "$ROOT/scripts/trent-record-e2e.sh" "$TRENT_REPORT" >"$WORK/trent-record-env-file.out"
grep -F '"id":12345' "$WORK/trent-record-env-file.out" >/dev/null
jq -e '.values.Project == "111764"' "$FAKE_CURL_BODY" >/dev/null

TRENT_OVERRIDE_ENV="$WORK/trent-override.env"
cat >"$TRENT_OVERRIDE_ENV" <<'EOF'
CODEXDOCK_TRENT_PROJECT=222333
CODEXDOCK_TRENT_ROADMAP_IDS='222334 222335'
EOF
: >"$FAKE_CURL_LOG"
CODEXDOCK_FAKE_CURL_LOG="$FAKE_CURL_LOG" \
  CODEXDOCK_FAKE_CURL_BODY="$FAKE_CURL_BODY" \
  CODEXDOCK_TRENT_TOKEN=test-token \
  CODEXDOCK_TRENT_PROJECT=111764 \
  CODEXDOCK_TRENT_BASE_URL=https://trent.example \
  CODEXDOCK_TRENT_ENV_FILE="$TRENT_OVERRIDE_ENV" \
  PATH="$FAKE_BIN:$PATH" \
  "$ROOT/scripts/trent-record-e2e.sh" "$TRENT_REPORT" >"$WORK/trent-record-env-override.out"
jq -e '.values.Project == "111764"' "$FAKE_CURL_BODY" >/dev/null

TRENT_KEY_REPORT="$WORK/trent-report-key"
cp -R "$TRENT_REPORT" "$TRENT_KEY_REPORT"
sed 's/^ssh_authorized_key_set=no$/ssh_authorized_key_set=yes/' "$TRENT_REPORT/context.txt" >"$TRENT_KEY_REPORT/context.txt"
cat >"$TRENT_KEY_REPORT/prepare.cmd" <<'EOF'
env HOME=/tmp/codexdock-home /tmp/codexdock doctor homepc --repair --yes --target-os linux --role codex-host --ssh-authorized-key ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICodexDockSmokeKey macbook
EOF
CODEXDOCK_FAKE_CURL_LOG="$FAKE_CURL_LOG" \
  CODEXDOCK_FAKE_CURL_BODY="$FAKE_CURL_BODY" \
  CODEXDOCK_TRENT_TOKEN=test-token \
  CODEXDOCK_TRENT_PROJECT=111764 \
  CODEXDOCK_TRENT_BASE_URL=https://trent.example \
  PATH="$FAKE_BIN:$PATH" \
  "$ROOT/scripts/trent-record-e2e.sh" "$TRENT_KEY_REPORT" >"$WORK/trent-record-key.out"
jq -e '.values.Content | contains("--ssh-authorized-key <redacted>")' "$FAKE_CURL_BODY" >/dev/null
jq -e '.values.Content | contains("AAAAC3NzaC1lZDI1NTE5AAAAICodexDockSmokeKey") | not' "$FAKE_CURL_BODY" >/dev/null

TRENT_SENSITIVE_REPORT="$WORK/trent-report-sensitive"
cp -R "$TRENT_REPORT" "$TRENT_SENSITIVE_REPORT"
sed 's/^ssh_authorized_key_set=no$/ssh_authorized_key_set=yes/' "$TRENT_REPORT/context.txt" >"$TRENT_SENSITIVE_REPORT/context.txt"
cat >"$TRENT_SENSITIVE_REPORT/prepare.cmd" <<'EOF'
env HOME=/tmp/codexdock-home /tmp/codexdock doctor homepc --repair --yes --target-os linux --role codex-host --ssh-authorized-key=ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEqualsStyleKey macbook
EOF
cat >"$TRENT_SENSITIVE_REPORT/init.cmd" <<'EOF'
env HOME=/tmp/codexdock-home /tmp/codexdock register macbook personal --control-url https://control.example --join --enrollment-key cdock-secret-enrollment-key --ssh-user manoj
EOF
CODEXDOCK_FAKE_CURL_LOG="$FAKE_CURL_LOG" \
  CODEXDOCK_FAKE_CURL_BODY="$FAKE_CURL_BODY" \
  CODEXDOCK_TRENT_TOKEN=test-token \
  CODEXDOCK_TRENT_PROJECT=111764 \
  CODEXDOCK_TRENT_BASE_URL=https://trent.example \
  PATH="$FAKE_BIN:$PATH" \
  "$ROOT/scripts/trent-record-e2e.sh" "$TRENT_SENSITIVE_REPORT" >"$WORK/trent-record-sensitive.out"
jq -e '.values.Content | contains("--ssh-authorized-key=<redacted>")' "$FAKE_CURL_BODY" >/dev/null
jq -e '.values.Content | contains("AAAAC3NzaC1lZDI1NTE5AAAAIEqualsStyleKey") | not' "$FAKE_CURL_BODY" >/dev/null
jq -e '.values.Content | contains("--enrollment-key <redacted>")' "$FAKE_CURL_BODY" >/dev/null
jq -e '.values.Content | contains("cdock-secret-enrollment-key") | not' "$FAKE_CURL_BODY" >/dev/null

: >"$FAKE_CURL_LOG"
CODEXDOCK_FAKE_CURL_LOG="$FAKE_CURL_LOG" \
  CODEXDOCK_FAKE_CURL_BODY="$FAKE_CURL_BODY" \
  CODEXDOCK_TRENT_TOKEN=test-token \
  CODEXDOCK_TRENT_BASE_URL=https://trent.example \
  PATH="$FAKE_BIN:$PATH" \
  "$ROOT/scripts/trent-close-roadmap.sh" "$TRENT_REPORT" >"$WORK/trent-close.out"
grep -F "closed roadmap item 111768" "$WORK/trent-close.out" >/dev/null
grep -F "closed roadmap item 111769" "$WORK/trent-close.out" >/dev/null
grep -F "closed roadmap item 111770" "$WORK/trent-close.out" >/dev/null
grep -F "closed roadmap item 111771" "$WORK/trent-close.out" >/dev/null
grep -F "https://trent.example/api/v1/data/CodexDock/RoadmapItem/111768" "$FAKE_CURL_LOG" >/dev/null
grep -F "https://trent.example/api/v1/data/CodexDock/RoadmapItem/111769" "$FAKE_CURL_LOG" >/dev/null
grep -F "https://trent.example/api/v1/data/CodexDock/RoadmapItem/111770" "$FAKE_CURL_LOG" >/dev/null
grep -F "https://trent.example/api/v1/data/CodexDock/RoadmapItem/111771" "$FAKE_CURL_LOG" >/dev/null
grep -F "Authorization: Bearer test-token" "$FAKE_CURL_LOG" >/dev/null

: >"$FAKE_CURL_LOG"
CODEXDOCK_FAKE_CURL_LOG="$FAKE_CURL_LOG" \
  CODEXDOCK_FAKE_CURL_BODY="$FAKE_CURL_BODY" \
  CODEXDOCK_TRENT_TOKEN=test-token \
  CODEXDOCK_TRENT_BASE_URL=https://trent.example \
  CODEXDOCK_TRENT_ENV_FILE="$TRENT_DIRECT_ENV" \
  PATH="$FAKE_BIN:$PATH" \
  "$ROOT/scripts/trent-close-roadmap.sh" "$TRENT_REPORT" >"$WORK/trent-close-env-file.out"
grep -F "closed roadmap item 222001" "$WORK/trent-close-env-file.out" >/dev/null
grep -F "closed roadmap item 222002" "$WORK/trent-close-env-file.out" >/dev/null
grep -F "https://trent.example/api/v1/data/CodexDock/RoadmapItem/222001" "$FAKE_CURL_LOG" >/dev/null
grep -F "https://trent.example/api/v1/data/CodexDock/RoadmapItem/222002" "$FAKE_CURL_LOG" >/dev/null

: >"$FAKE_CURL_LOG"
CODEXDOCK_FAKE_CURL_LOG="$FAKE_CURL_LOG" \
  CODEXDOCK_FAKE_CURL_BODY="$FAKE_CURL_BODY" \
  CODEXDOCK_TRENT_TOKEN=test-token \
  CODEXDOCK_TRENT_BASE_URL=https://trent.example \
  CODEXDOCK_TRENT_ROADMAP_IDS='111768 111769' \
  CODEXDOCK_TRENT_ENV_FILE="$TRENT_OVERRIDE_ENV" \
  PATH="$FAKE_BIN:$PATH" \
  "$ROOT/scripts/trent-close-roadmap.sh" "$TRENT_REPORT" >"$WORK/trent-close-env-override.out"
grep -F "closed roadmap item 111768" "$WORK/trent-close-env-override.out" >/dev/null
grep -F "closed roadmap item 111769" "$WORK/trent-close-env-override.out" >/dev/null
grep -F "https://trent.example/api/v1/data/CodexDock/RoadmapItem/111768" "$FAKE_CURL_LOG" >/dev/null
grep -F "https://trent.example/api/v1/data/CodexDock/RoadmapItem/111769" "$FAKE_CURL_LOG" >/dev/null

: >"$FAKE_CURL_LOG"
CODEXDOCK_FAKE_CURL_LOG="$FAKE_CURL_LOG" \
  CODEXDOCK_FAKE_CURL_BODY="$FAKE_CURL_BODY" \
  CODEXDOCK_TRENT_TOKEN=test-token \
  CODEXDOCK_TRENT_PROJECT=111764 \
  CODEXDOCK_TRENT_BASE_URL=https://trent.example \
  PATH="$FAKE_BIN:$PATH" \
  "$ROOT/scripts/trent-finalize-e2e.sh" "$TRENT_REPORT" >"$WORK/trent-finalize.out"
grep -F "validated remote E2E report" "$WORK/trent-finalize.out" >/dev/null
grep -F '"id":12345' "$WORK/trent-finalize.out" >/dev/null
grep -F "recorded remote E2E report in TrentPlatform" "$WORK/trent-finalize.out" >/dev/null
grep -F "closed roadmap item 111768" "$WORK/trent-finalize.out" >/dev/null
grep -F "closed roadmap item 111769" "$WORK/trent-finalize.out" >/dev/null
grep -F "closed roadmap item 111770" "$WORK/trent-finalize.out" >/dev/null
grep -F "closed roadmap item 111771" "$WORK/trent-finalize.out" >/dev/null
grep -F "https://trent.example/api/v1/data/CodexDock/Artifact" "$FAKE_CURL_LOG" >/dev/null
grep -F "https://trent.example/api/v1/data/CodexDock/RoadmapItem/111768" "$FAKE_CURL_LOG" >/dev/null
grep -F "https://trent.example/api/v1/data/CodexDock/RoadmapItem/111769" "$FAKE_CURL_LOG" >/dev/null
grep -F "https://trent.example/api/v1/data/CodexDock/RoadmapItem/111770" "$FAKE_CURL_LOG" >/dev/null
grep -F "https://trent.example/api/v1/data/CodexDock/RoadmapItem/111771" "$FAKE_CURL_LOG" >/dev/null

: >"$FAKE_CURL_LOG"
CODEXDOCK_FAKE_CURL_LOG="$FAKE_CURL_LOG" \
  CODEXDOCK_FAKE_CURL_BODY="$FAKE_CURL_BODY" \
  CODEXDOCK_TRENT_TOKEN=test-token \
  CODEXDOCK_TRENT_BASE_URL=https://trent.example \
  CODEXDOCK_TRENT_ENV_FILE="$TRENT_DIRECT_ENV" \
  PATH="$FAKE_BIN:$PATH" \
  "$ROOT/scripts/trent-finalize-e2e.sh" "$TRENT_REPORT" >"$WORK/trent-finalize-env-file.out"
grep -F "validated remote E2E report" "$WORK/trent-finalize-env-file.out" >/dev/null
grep -F '"id":12345' "$WORK/trent-finalize-env-file.out" >/dev/null
grep -F "closed roadmap item 222001" "$WORK/trent-finalize-env-file.out" >/dev/null
grep -F "closed roadmap item 222002" "$WORK/trent-finalize-env-file.out" >/dev/null
grep -F "https://trent.example/api/v1/data/CodexDock/Artifact" "$FAKE_CURL_LOG" >/dev/null
grep -F "https://trent.example/api/v1/data/CodexDock/RoadmapItem/222001" "$FAKE_CURL_LOG" >/dev/null
grep -F "https://trent.example/api/v1/data/CodexDock/RoadmapItem/222002" "$FAKE_CURL_LOG" >/dev/null

: >"$FAKE_CURL_LOG"
CODEXDOCK_FAKE_CURL_LOG="$FAKE_CURL_LOG" \
  CODEXDOCK_FAKE_CURL_BODY="$FAKE_CURL_BODY" \
  CODEXDOCK_TRENT_TOKEN=test-token \
  CODEXDOCK_TRENT_PROJECT=111764 \
  CODEXDOCK_TRENT_ROADMAP_IDS='111768 111769' \
  CODEXDOCK_TRENT_BASE_URL=https://trent.example \
  CODEXDOCK_TRENT_ENV_FILE="$TRENT_OVERRIDE_ENV" \
  PATH="$FAKE_BIN:$PATH" \
  "$ROOT/scripts/trent-finalize-e2e.sh" "$TRENT_REPORT" >"$WORK/trent-finalize-env-override.out"
grep -F "closed roadmap item 111768" "$WORK/trent-finalize-env-override.out" >/dev/null
grep -F "closed roadmap item 111769" "$WORK/trent-finalize-env-override.out" >/dev/null
grep -F "https://trent.example/api/v1/data/CodexDock/RoadmapItem/111768" "$FAKE_CURL_LOG" >/dev/null
grep -F "https://trent.example/api/v1/data/CodexDock/RoadmapItem/111769" "$FAKE_CURL_LOG" >/dev/null

BAD_CONTEXT_CLOSE_REPORT="$WORK/bad-context-close-report"
cp -R "$TRENT_REPORT" "$BAD_CONTEXT_CLOSE_REPORT"
rm -f "$BAD_CONTEXT_CLOSE_REPORT/context.txt"
: >"$FAKE_CURL_LOG"
if CODEXDOCK_FAKE_CURL_LOG="$FAKE_CURL_LOG" \
  CODEXDOCK_FAKE_CURL_BODY="$FAKE_CURL_BODY" \
  CODEXDOCK_TRENT_TOKEN=test-token \
  CODEXDOCK_TRENT_BASE_URL=https://trent.example \
  PATH="$FAKE_BIN:$PATH" \
  "$ROOT/scripts/trent-close-roadmap.sh" "$BAD_CONTEXT_CLOSE_REPORT" >"$WORK/trent-close-bad-context.out" 2>&1; then
  echo "expected TrentPlatform roadmap closure to reject reports with missing context" >&2
  exit 1
fi
grep -F "remote E2E report is missing required artifact: context.txt" "$WORK/trent-close-bad-context.out" >/dev/null
test ! -s "$FAKE_CURL_LOG"

BAD_CONTEXT_FIELD_CLOSE_REPORT="$WORK/bad-context-field-close-report"
cp -R "$TRENT_REPORT" "$BAD_CONTEXT_FIELD_CLOSE_REPORT"
sed '/^target_arch=/d' "$TRENT_REPORT/context.txt" >"$BAD_CONTEXT_FIELD_CLOSE_REPORT/context.txt"
: >"$FAKE_CURL_LOG"
if CODEXDOCK_FAKE_CURL_LOG="$FAKE_CURL_LOG" \
  CODEXDOCK_FAKE_CURL_BODY="$FAKE_CURL_BODY" \
  CODEXDOCK_TRENT_TOKEN=test-token \
  CODEXDOCK_TRENT_BASE_URL=https://trent.example \
  PATH="$FAKE_BIN:$PATH" \
  "$ROOT/scripts/trent-close-roadmap.sh" "$BAD_CONTEXT_FIELD_CLOSE_REPORT" >"$WORK/trent-close-bad-context-field.out" 2>&1; then
  echo "expected TrentPlatform roadmap closure to reject reports with incomplete context" >&2
  exit 1
fi
grep -F "remote E2E report artifact did not contain expected text: context.txt" "$WORK/trent-close-bad-context-field.out" >/dev/null
test ! -s "$FAKE_CURL_LOG"

BAD_CONTEXT_MISMATCH_CLOSE_REPORT="$WORK/bad-context-mismatch-close-report"
cp -R "$TRENT_REPORT" "$BAD_CONTEXT_MISMATCH_CLOSE_REPORT"
sed 's/^machine=homepc$/machine=otherpc/' "$TRENT_REPORT/context.txt" >"$BAD_CONTEXT_MISMATCH_CLOSE_REPORT/context.txt"
: >"$FAKE_CURL_LOG"
if CODEXDOCK_FAKE_CURL_LOG="$FAKE_CURL_LOG" \
  CODEXDOCK_FAKE_CURL_BODY="$FAKE_CURL_BODY" \
  CODEXDOCK_TRENT_TOKEN=test-token \
  CODEXDOCK_TRENT_BASE_URL=https://trent.example \
  PATH="$FAKE_BIN:$PATH" \
  "$ROOT/scripts/trent-close-roadmap.sh" "$BAD_CONTEXT_MISMATCH_CLOSE_REPORT" >"$WORK/trent-close-bad-context-mismatch.out" 2>&1; then
  echo "expected TrentPlatform roadmap closure to reject mismatched context" >&2
  exit 1
fi
grep -F "remote E2E report context machine does not match result: otherpc != homepc" "$WORK/trent-close-bad-context-mismatch.out" >/dev/null
test ! -s "$FAKE_CURL_LOG"

BLANK_IDENTITY_CLOSE_REPORT="$WORK/blank-identity-close-report"
cp -R "$TRENT_REPORT" "$BLANK_IDENTITY_CLOSE_REPORT"
sed 's/^ssh_user=manoj$/ssh_user=/' "$TRENT_REPORT/context.txt" >"$BLANK_IDENTITY_CLOSE_REPORT/context.txt"
cat >"$BLANK_IDENTITY_CLOSE_REPORT/init.cmd" <<'EOF'
env HOME=/tmp/codexdock-home /tmp/codexdock init --network personal --machine homepc --host 100.64.0.2 --ssh-user  --ssh-port 22 --workspace ~/code --session codexdock-e2e --agent codex
EOF
: >"$FAKE_CURL_LOG"
if CODEXDOCK_FAKE_CURL_LOG="$FAKE_CURL_LOG" \
  CODEXDOCK_FAKE_CURL_BODY="$FAKE_CURL_BODY" \
  CODEXDOCK_TRENT_TOKEN=test-token \
  CODEXDOCK_TRENT_BASE_URL=https://trent.example \
  PATH="$FAKE_BIN:$PATH" \
  "$ROOT/scripts/trent-close-roadmap.sh" "$BLANK_IDENTITY_CLOSE_REPORT" >"$WORK/trent-close-blank-identity.out" 2>&1; then
  echo "expected TrentPlatform roadmap closure to reject blank report identity fields" >&2
  exit 1
fi
grep -F "remote E2E report context ssh_user cannot be blank" "$WORK/trent-close-blank-identity.out" >/dev/null
test ! -s "$FAKE_CURL_LOG"

BAD_CONTEXT_DUPLICATE_CLOSE_REPORT="$WORK/bad-context-duplicate-close-report"
cp -R "$TRENT_REPORT" "$BAD_CONTEXT_DUPLICATE_CLOSE_REPORT"
printf 'machine=otherpc\n' >>"$BAD_CONTEXT_DUPLICATE_CLOSE_REPORT/context.txt"
: >"$FAKE_CURL_LOG"
if CODEXDOCK_FAKE_CURL_LOG="$FAKE_CURL_LOG" \
  CODEXDOCK_FAKE_CURL_BODY="$FAKE_CURL_BODY" \
  CODEXDOCK_TRENT_TOKEN=test-token \
  CODEXDOCK_TRENT_BASE_URL=https://trent.example \
  PATH="$FAKE_BIN:$PATH" \
  "$ROOT/scripts/trent-close-roadmap.sh" "$BAD_CONTEXT_DUPLICATE_CLOSE_REPORT" >"$WORK/trent-close-bad-context-duplicate.out" 2>&1; then
  echo "expected TrentPlatform roadmap closure to reject duplicate context fields" >&2
  exit 1
fi
grep -F "remote E2E report context field appears more than once: machine" "$WORK/trent-close-bad-context-duplicate.out" >/dev/null
test ! -s "$FAKE_CURL_LOG"

BAD_RESULT_DUPLICATE_CLOSE_REPORT="$WORK/bad-result-duplicate-close-report"
cp -R "$TRENT_REPORT" "$BAD_RESULT_DUPLICATE_CLOSE_REPORT"
printf 'machine=otherpc\n' >>"$BAD_RESULT_DUPLICATE_CLOSE_REPORT/result.txt"
: >"$FAKE_CURL_LOG"
if CODEXDOCK_FAKE_CURL_LOG="$FAKE_CURL_LOG" \
  CODEXDOCK_FAKE_CURL_BODY="$FAKE_CURL_BODY" \
  CODEXDOCK_TRENT_TOKEN=test-token \
  CODEXDOCK_TRENT_BASE_URL=https://trent.example \
  PATH="$FAKE_BIN:$PATH" \
  "$ROOT/scripts/trent-close-roadmap.sh" "$BAD_RESULT_DUPLICATE_CLOSE_REPORT" >"$WORK/trent-close-bad-result-duplicate.out" 2>&1; then
  echo "expected TrentPlatform roadmap closure to reject duplicate result fields" >&2
  exit 1
fi
grep -F "remote E2E report result field appears more than once: machine" "$WORK/trent-close-bad-result-duplicate.out" >/dev/null
test ! -s "$FAKE_CURL_LOG"

BAD_RESULT_SESSION_DUPLICATE_CLOSE_REPORT="$WORK/bad-result-session-duplicate-close-report"
cp -R "$TRENT_REPORT" "$BAD_RESULT_SESSION_DUPLICATE_CLOSE_REPORT"
printf 'session_stopped=no\n' >>"$BAD_RESULT_SESSION_DUPLICATE_CLOSE_REPORT/result.txt"
: >"$FAKE_CURL_LOG"
if CODEXDOCK_FAKE_CURL_LOG="$FAKE_CURL_LOG" \
  CODEXDOCK_FAKE_CURL_BODY="$FAKE_CURL_BODY" \
  CODEXDOCK_TRENT_TOKEN=test-token \
  CODEXDOCK_TRENT_BASE_URL=https://trent.example \
  PATH="$FAKE_BIN:$PATH" \
  "$ROOT/scripts/trent-close-roadmap.sh" "$BAD_RESULT_SESSION_DUPLICATE_CLOSE_REPORT" >"$WORK/trent-close-bad-result-session-duplicate.out" 2>&1; then
  echo "expected TrentPlatform roadmap closure to reject duplicate result session fields" >&2
  exit 1
fi
grep -F "remote E2E report result field appears more than once: session_stopped" "$WORK/trent-close-bad-result-session-duplicate.out" >/dev/null
test ! -s "$FAKE_CURL_LOG"

BAD_RESULT_CLEANUP_MISSING_CLOSE_REPORT="$WORK/bad-result-cleanup-missing-close-report"
cp -R "$TRENT_REPORT" "$BAD_RESULT_CLEANUP_MISSING_CLOSE_REPORT"
sed '/^cleanup_attempted=/d' "$TRENT_REPORT/result.txt" >"$BAD_RESULT_CLEANUP_MISSING_CLOSE_REPORT/result.txt"
: >"$FAKE_CURL_LOG"
if CODEXDOCK_FAKE_CURL_LOG="$FAKE_CURL_LOG" \
  CODEXDOCK_FAKE_CURL_BODY="$FAKE_CURL_BODY" \
  CODEXDOCK_TRENT_TOKEN=test-token \
  CODEXDOCK_TRENT_BASE_URL=https://trent.example \
  PATH="$FAKE_BIN:$PATH" \
  "$ROOT/scripts/trent-close-roadmap.sh" "$BAD_RESULT_CLEANUP_MISSING_CLOSE_REPORT" >"$WORK/trent-close-bad-result-cleanup-missing.out" 2>&1; then
  echo "expected TrentPlatform roadmap closure to reject missing result cleanup fields" >&2
  exit 1
fi
grep -F "remote E2E report result field is missing: cleanup_attempted" "$WORK/trent-close-bad-result-cleanup-missing.out" >/dev/null
test ! -s "$FAKE_CURL_LOG"

BAD_RESULT_CLEANUP_FLAG_CLOSE_REPORT="$WORK/bad-result-cleanup-flag-close-report"
cp -R "$TRENT_REPORT" "$BAD_RESULT_CLEANUP_FLAG_CLOSE_REPORT"
sed 's/^cleanup_attempted=no$/cleanup_attempted=maybe/' "$TRENT_REPORT/result.txt" >"$BAD_RESULT_CLEANUP_FLAG_CLOSE_REPORT/result.txt"
: >"$FAKE_CURL_LOG"
if CODEXDOCK_FAKE_CURL_LOG="$FAKE_CURL_LOG" \
  CODEXDOCK_FAKE_CURL_BODY="$FAKE_CURL_BODY" \
  CODEXDOCK_TRENT_TOKEN=test-token \
  CODEXDOCK_TRENT_BASE_URL=https://trent.example \
  PATH="$FAKE_BIN:$PATH" \
  "$ROOT/scripts/trent-close-roadmap.sh" "$BAD_RESULT_CLEANUP_FLAG_CLOSE_REPORT" >"$WORK/trent-close-bad-result-cleanup-flag.out" 2>&1; then
  echo "expected TrentPlatform roadmap closure to reject invalid result cleanup flag" >&2
  exit 1
fi
grep -F "remote E2E report result cleanup_attempted must be yes or no: maybe" "$WORK/trent-close-bad-result-cleanup-flag.out" >/dev/null
test ! -s "$FAKE_CURL_LOG"

BAD_RESULT_CLEANUP_EXIT_CLOSE_REPORT="$WORK/bad-result-cleanup-exit-close-report"
cp -R "$TRENT_REPORT" "$BAD_RESULT_CLEANUP_EXIT_CLOSE_REPORT"
sed 's/^cleanup_exit_code=not_applicable$/cleanup_exit_code=0/' "$TRENT_REPORT/result.txt" >"$BAD_RESULT_CLEANUP_EXIT_CLOSE_REPORT/result.txt"
: >"$FAKE_CURL_LOG"
if CODEXDOCK_FAKE_CURL_LOG="$FAKE_CURL_LOG" \
  CODEXDOCK_FAKE_CURL_BODY="$FAKE_CURL_BODY" \
  CODEXDOCK_TRENT_TOKEN=test-token \
  CODEXDOCK_TRENT_BASE_URL=https://trent.example \
  PATH="$FAKE_BIN:$PATH" \
  "$ROOT/scripts/trent-close-roadmap.sh" "$BAD_RESULT_CLEANUP_EXIT_CLOSE_REPORT" >"$WORK/trent-close-bad-result-cleanup-exit.out" 2>&1; then
  echo "expected TrentPlatform roadmap closure to reject inconsistent result cleanup exit code" >&2
  exit 1
fi
grep -F "remote E2E report result cleanup_exit_code must be not_applicable when cleanup_attempted=no: 0" "$WORK/trent-close-bad-result-cleanup-exit.out" >/dev/null
test ! -s "$FAKE_CURL_LOG"

MISSING_CLEANUP_ARTIFACTS_CLOSE_REPORT="$WORK/missing-cleanup-artifacts-close-report"
cp -R "$TRENT_REPORT" "$MISSING_CLEANUP_ARTIFACTS_CLOSE_REPORT"
sed -e 's/^cleanup_attempted=no$/cleanup_attempted=yes/' \
  -e 's/^cleanup_exit_code=not_applicable$/cleanup_exit_code=0/' \
  "$TRENT_REPORT/result.txt" >"$MISSING_CLEANUP_ARTIFACTS_CLOSE_REPORT/result.txt"
: >"$FAKE_CURL_LOG"
if CODEXDOCK_FAKE_CURL_LOG="$FAKE_CURL_LOG" \
  CODEXDOCK_FAKE_CURL_BODY="$FAKE_CURL_BODY" \
  CODEXDOCK_TRENT_TOKEN=test-token \
  CODEXDOCK_TRENT_BASE_URL=https://trent.example \
  PATH="$FAKE_BIN:$PATH" \
  "$ROOT/scripts/trent-close-roadmap.sh" "$MISSING_CLEANUP_ARTIFACTS_CLOSE_REPORT" >"$WORK/trent-close-missing-cleanup-artifacts.out" 2>&1; then
  echo "expected TrentPlatform roadmap closure to reject cleanup attempts without cleanup artifacts" >&2
  exit 1
fi
grep -F "remote E2E report is missing required artifact: cleanup_stop.cmd" "$WORK/trent-close-missing-cleanup-artifacts.out" >/dev/null
test ! -s "$FAKE_CURL_LOG"

FAILED_CLEANUP_EXIT_CLOSE_REPORT="$WORK/failed-cleanup-exit-close-report"
cp -R "$TRENT_REPORT" "$FAILED_CLEANUP_EXIT_CLOSE_REPORT"
sed -e 's/^cleanup_attempted=no$/cleanup_attempted=yes/' \
  -e 's/^cleanup_exit_code=not_applicable$/cleanup_exit_code=1/' \
  "$TRENT_REPORT/result.txt" >"$FAILED_CLEANUP_EXIT_CLOSE_REPORT/result.txt"
cat >"$FAILED_CLEANUP_EXIT_CLOSE_REPORT/cleanup_stop.cmd" <<'EOF'
env HOME=/tmp/codexdock-home /tmp/codexdock stop homepc --force
EOF
cat >"$FAILED_CLEANUP_EXIT_CLOSE_REPORT/cleanup_stop.out" <<'EOF'
cleanup stop failed
EOF
cat >"$FAILED_CLEANUP_EXIT_CLOSE_REPORT/cleanup_stop.err" <<'EOF'
exit status 1
EOF
: >"$FAKE_CURL_LOG"
if CODEXDOCK_FAKE_CURL_LOG="$FAKE_CURL_LOG" \
  CODEXDOCK_FAKE_CURL_BODY="$FAKE_CURL_BODY" \
  CODEXDOCK_TRENT_TOKEN=test-token \
  CODEXDOCK_TRENT_BASE_URL=https://trent.example \
  PATH="$FAKE_BIN:$PATH" \
  "$ROOT/scripts/trent-close-roadmap.sh" "$FAILED_CLEANUP_EXIT_CLOSE_REPORT" >"$WORK/trent-close-failed-cleanup-exit.out" 2>&1; then
  echo "expected TrentPlatform roadmap closure to reject successful reports with failed cleanup" >&2
  exit 1
fi
grep -F "remote E2E report result cleanup_exit_code must be 0 when cleanup_attempted=yes: 1" "$WORK/trent-close-failed-cleanup-exit.out" >/dev/null
test ! -s "$FAKE_CURL_LOG"

BAD_CONTEXT_MODE_CLOSE_REPORT="$WORK/bad-context-mode-close-report"
cp -R "$TRENT_REPORT" "$BAD_CONTEXT_MODE_CLOSE_REPORT"
sed 's/^adopt=0$/adopt=1/' "$TRENT_REPORT/context.txt" >"$BAD_CONTEXT_MODE_CLOSE_REPORT/context.txt"
: >"$FAKE_CURL_LOG"
if CODEXDOCK_FAKE_CURL_LOG="$FAKE_CURL_LOG" \
  CODEXDOCK_FAKE_CURL_BODY="$FAKE_CURL_BODY" \
  CODEXDOCK_TRENT_TOKEN=test-token \
  CODEXDOCK_TRENT_BASE_URL=https://trent.example \
  PATH="$FAKE_BIN:$PATH" \
  "$ROOT/scripts/trent-close-roadmap.sh" "$BAD_CONTEXT_MODE_CLOSE_REPORT" >"$WORK/trent-close-bad-context-mode.out" 2>&1; then
  echo "expected TrentPlatform roadmap closure to reject mode-mismatched context" >&2
  exit 1
fi
grep -F "remote E2E report context adopt does not match artifacts: 1 != 0" "$WORK/trent-close-bad-context-mode.out" >/dev/null
test ! -s "$FAKE_CURL_LOG"

BAD_CONTEXT_PREPARE_CLOSE_REPORT="$WORK/bad-context-prepare-close-report"
cp -R "$TRENT_REPORT" "$BAD_CONTEXT_PREPARE_CLOSE_REPORT"
sed 's/^prepare=1$/prepare=0/' "$TRENT_REPORT/context.txt" >"$BAD_CONTEXT_PREPARE_CLOSE_REPORT/context.txt"
: >"$FAKE_CURL_LOG"
if CODEXDOCK_FAKE_CURL_LOG="$FAKE_CURL_LOG" \
  CODEXDOCK_FAKE_CURL_BODY="$FAKE_CURL_BODY" \
  CODEXDOCK_TRENT_TOKEN=test-token \
  CODEXDOCK_TRENT_BASE_URL=https://trent.example \
  PATH="$FAKE_BIN:$PATH" \
  "$ROOT/scripts/trent-close-roadmap.sh" "$BAD_CONTEXT_PREPARE_CLOSE_REPORT" >"$WORK/trent-close-bad-context-prepare.out" 2>&1; then
  echo "expected TrentPlatform roadmap closure to reject prepare-mismatched context" >&2
  exit 1
fi
grep -F "remote E2E report context prepare does not match artifacts: 0 != 1" "$WORK/trent-close-bad-context-prepare.out" >/dev/null
test ! -s "$FAKE_CURL_LOG"

BAD_CONTEXT_ARCH_CLOSE_REPORT="$WORK/bad-context-arch-close-report"
cp -R "$TRENT_REPORT" "$BAD_CONTEXT_ARCH_CLOSE_REPORT"
sed 's/^target_arch=amd64$/target_arch=mips/' "$TRENT_REPORT/context.txt" >"$BAD_CONTEXT_ARCH_CLOSE_REPORT/context.txt"
: >"$FAKE_CURL_LOG"
if CODEXDOCK_FAKE_CURL_LOG="$FAKE_CURL_LOG" \
  CODEXDOCK_FAKE_CURL_BODY="$FAKE_CURL_BODY" \
  CODEXDOCK_TRENT_TOKEN=test-token \
  CODEXDOCK_TRENT_BASE_URL=https://trent.example \
  PATH="$FAKE_BIN:$PATH" \
  "$ROOT/scripts/trent-close-roadmap.sh" "$BAD_CONTEXT_ARCH_CLOSE_REPORT" >"$WORK/trent-close-bad-context-arch.out" 2>&1; then
  echo "expected TrentPlatform roadmap closure to reject unsupported context target architecture" >&2
  exit 1
fi
grep -F "remote E2E report context target_arch is unsupported: mips" "$WORK/trent-close-bad-context-arch.out" >/dev/null
test ! -s "$FAKE_CURL_LOG"

BAD_CONTEXT_PORT_CLOSE_REPORT="$WORK/bad-context-port-close-report"
cp -R "$TRENT_REPORT" "$BAD_CONTEXT_PORT_CLOSE_REPORT"
sed 's/^ssh_port=22$/ssh_port=abc/' "$TRENT_REPORT/context.txt" >"$BAD_CONTEXT_PORT_CLOSE_REPORT/context.txt"
: >"$FAKE_CURL_LOG"
if CODEXDOCK_FAKE_CURL_LOG="$FAKE_CURL_LOG" \
  CODEXDOCK_FAKE_CURL_BODY="$FAKE_CURL_BODY" \
  CODEXDOCK_TRENT_TOKEN=test-token \
  CODEXDOCK_TRENT_BASE_URL=https://trent.example \
  PATH="$FAKE_BIN:$PATH" \
  "$ROOT/scripts/trent-close-roadmap.sh" "$BAD_CONTEXT_PORT_CLOSE_REPORT" >"$WORK/trent-close-bad-context-port.out" 2>&1; then
  echo "expected TrentPlatform roadmap closure to reject invalid context SSH port" >&2
  exit 1
fi
grep -F "remote E2E report context ssh_port must be a positive integer: abc" "$WORK/trent-close-bad-context-port.out" >/dev/null
test ! -s "$FAKE_CURL_LOG"

BAD_CONTEXT_LOG_LINES_CLOSE_REPORT="$WORK/bad-context-log-lines-close-report"
cp -R "$TRENT_REPORT" "$BAD_CONTEXT_LOG_LINES_CLOSE_REPORT"
sed 's/^log_lines=40$/log_lines=0/' "$TRENT_REPORT/context.txt" >"$BAD_CONTEXT_LOG_LINES_CLOSE_REPORT/context.txt"
: >"$FAKE_CURL_LOG"
if CODEXDOCK_FAKE_CURL_LOG="$FAKE_CURL_LOG" \
  CODEXDOCK_FAKE_CURL_BODY="$FAKE_CURL_BODY" \
  CODEXDOCK_TRENT_TOKEN=test-token \
  CODEXDOCK_TRENT_BASE_URL=https://trent.example \
  PATH="$FAKE_BIN:$PATH" \
  "$ROOT/scripts/trent-close-roadmap.sh" "$BAD_CONTEXT_LOG_LINES_CLOSE_REPORT" >"$WORK/trent-close-bad-context-log-lines.out" 2>&1; then
  echo "expected TrentPlatform roadmap closure to reject invalid context log line count" >&2
  exit 1
fi
grep -F "remote E2E report context log_lines must be a positive integer: 0" "$WORK/trent-close-bad-context-log-lines.out" >/dev/null
test ! -s "$FAKE_CURL_LOG"

BAD_CONTEXT_WORKSPACE_CLOSE_REPORT="$WORK/bad-context-workspace-close-report"
cp -R "$TRENT_REPORT" "$BAD_CONTEXT_WORKSPACE_CLOSE_REPORT"
sed 's|^workspace=~/code$|workspace=   |' "$TRENT_REPORT/context.txt" >"$BAD_CONTEXT_WORKSPACE_CLOSE_REPORT/context.txt"
: >"$FAKE_CURL_LOG"
if CODEXDOCK_FAKE_CURL_LOG="$FAKE_CURL_LOG" \
  CODEXDOCK_FAKE_CURL_BODY="$FAKE_CURL_BODY" \
  CODEXDOCK_TRENT_TOKEN=test-token \
  CODEXDOCK_TRENT_BASE_URL=https://trent.example \
  PATH="$FAKE_BIN:$PATH" \
  "$ROOT/scripts/trent-close-roadmap.sh" "$BAD_CONTEXT_WORKSPACE_CLOSE_REPORT" >"$WORK/trent-close-bad-context-workspace.out" 2>&1; then
  echo "expected TrentPlatform roadmap closure to reject blank context workspace" >&2
  exit 1
fi
grep -F "remote E2E report context workspace cannot be blank" "$WORK/trent-close-bad-context-workspace.out" >/dev/null
test ! -s "$FAKE_CURL_LOG"

BAD_CONTEXT_SESSION_CLOSE_REPORT="$WORK/bad-context-session-close-report"
cp -R "$TRENT_REPORT" "$BAD_CONTEXT_SESSION_CLOSE_REPORT"
sed 's/^session=codexdock-e2e$/session=bad session/' "$TRENT_REPORT/context.txt" >"$BAD_CONTEXT_SESSION_CLOSE_REPORT/context.txt"
sed 's/^session=codexdock-e2e$/session=bad session/' "$TRENT_REPORT/result.txt" >"$BAD_CONTEXT_SESSION_CLOSE_REPORT/result.txt"
: >"$FAKE_CURL_LOG"
if CODEXDOCK_FAKE_CURL_LOG="$FAKE_CURL_LOG" \
  CODEXDOCK_FAKE_CURL_BODY="$FAKE_CURL_BODY" \
  CODEXDOCK_TRENT_TOKEN=test-token \
  CODEXDOCK_TRENT_BASE_URL=https://trent.example \
  PATH="$FAKE_BIN:$PATH" \
  "$ROOT/scripts/trent-close-roadmap.sh" "$BAD_CONTEXT_SESSION_CLOSE_REPORT" >"$WORK/trent-close-bad-context-session.out" 2>&1; then
  echo "expected TrentPlatform roadmap closure to reject invalid context session" >&2
  exit 1
fi
grep -F "remote E2E report context session must contain only letters, numbers, underscores, or hyphens" "$WORK/trent-close-bad-context-session.out" >/dev/null
test ! -s "$FAKE_CURL_LOG"

BAD_CONTEXT_AGENT_CLOSE_REPORT="$WORK/bad-context-agent-close-report"
cp -R "$TRENT_REPORT" "$BAD_CONTEXT_AGENT_CLOSE_REPORT"
sed 's/^agent=codex$/agent=   /' "$TRENT_REPORT/context.txt" >"$BAD_CONTEXT_AGENT_CLOSE_REPORT/context.txt"
: >"$FAKE_CURL_LOG"
if CODEXDOCK_FAKE_CURL_LOG="$FAKE_CURL_LOG" \
  CODEXDOCK_FAKE_CURL_BODY="$FAKE_CURL_BODY" \
  CODEXDOCK_TRENT_TOKEN=test-token \
  CODEXDOCK_TRENT_BASE_URL=https://trent.example \
  PATH="$FAKE_BIN:$PATH" \
  "$ROOT/scripts/trent-close-roadmap.sh" "$BAD_CONTEXT_AGENT_CLOSE_REPORT" >"$WORK/trent-close-bad-context-agent.out" 2>&1; then
  echo "expected TrentPlatform roadmap closure to reject blank context agent" >&2
  exit 1
fi
grep -F "remote E2E report context agent cannot be blank" "$WORK/trent-close-bad-context-agent.out" >/dev/null
test ! -s "$FAKE_CURL_LOG"

BAD_CONTEXT_PROMPT_CLOSE_REPORT="$WORK/bad-context-prompt-close-report"
cp -R "$TRENT_REPORT" "$BAD_CONTEXT_PROMPT_CLOSE_REPORT"
sed 's/^prompt=codexdock smoke ping$/prompt=   /' "$TRENT_REPORT/context.txt" >"$BAD_CONTEXT_PROMPT_CLOSE_REPORT/context.txt"
: >"$FAKE_CURL_LOG"
if CODEXDOCK_FAKE_CURL_LOG="$FAKE_CURL_LOG" \
  CODEXDOCK_FAKE_CURL_BODY="$FAKE_CURL_BODY" \
  CODEXDOCK_TRENT_TOKEN=test-token \
  CODEXDOCK_TRENT_BASE_URL=https://trent.example \
  PATH="$FAKE_BIN:$PATH" \
  "$ROOT/scripts/trent-close-roadmap.sh" "$BAD_CONTEXT_PROMPT_CLOSE_REPORT" >"$WORK/trent-close-bad-context-prompt.out" 2>&1; then
  echo "expected TrentPlatform roadmap closure to reject blank context prompt" >&2
  exit 1
fi
grep -F "remote E2E report context prompt cannot be blank" "$WORK/trent-close-bad-context-prompt.out" >/dev/null
test ! -s "$FAKE_CURL_LOG"

BAD_CONTEXT_REQUIRE_SCP_CLOSE_REPORT="$WORK/bad-context-require-scp-close-report"
cp -R "$TRENT_REPORT" "$BAD_CONTEXT_REQUIRE_SCP_CLOSE_REPORT"
sed 's/^require_scp=0$/require_scp=2/' "$TRENT_REPORT/context.txt" >"$BAD_CONTEXT_REQUIRE_SCP_CLOSE_REPORT/context.txt"
: >"$FAKE_CURL_LOG"
if CODEXDOCK_FAKE_CURL_LOG="$FAKE_CURL_LOG" \
  CODEXDOCK_FAKE_CURL_BODY="$FAKE_CURL_BODY" \
  CODEXDOCK_TRENT_TOKEN=test-token \
  CODEXDOCK_TRENT_BASE_URL=https://trent.example \
  PATH="$FAKE_BIN:$PATH" \
  "$ROOT/scripts/trent-close-roadmap.sh" "$BAD_CONTEXT_REQUIRE_SCP_CLOSE_REPORT" >"$WORK/trent-close-bad-context-require-scp.out" 2>&1; then
  echo "expected TrentPlatform roadmap closure to reject invalid context require_scp flag" >&2
  exit 1
fi
grep -F "remote E2E report context require_scp must be 0 or 1: 2" "$WORK/trent-close-bad-context-require-scp.out" >/dev/null
test ! -s "$FAKE_CURL_LOG"

BAD_CONTEXT_KEY_FLAG_CLOSE_REPORT="$WORK/bad-context-key-flag-close-report"
cp -R "$TRENT_REPORT" "$BAD_CONTEXT_KEY_FLAG_CLOSE_REPORT"
sed 's/^ssh_authorized_key_set=no$/ssh_authorized_key_set=maybe/' "$TRENT_REPORT/context.txt" >"$BAD_CONTEXT_KEY_FLAG_CLOSE_REPORT/context.txt"
: >"$FAKE_CURL_LOG"
if CODEXDOCK_FAKE_CURL_LOG="$FAKE_CURL_LOG" \
  CODEXDOCK_FAKE_CURL_BODY="$FAKE_CURL_BODY" \
  CODEXDOCK_TRENT_TOKEN=test-token \
  CODEXDOCK_TRENT_BASE_URL=https://trent.example \
  PATH="$FAKE_BIN:$PATH" \
  "$ROOT/scripts/trent-close-roadmap.sh" "$BAD_CONTEXT_KEY_FLAG_CLOSE_REPORT" >"$WORK/trent-close-bad-context-key-flag.out" 2>&1; then
  echo "expected TrentPlatform roadmap closure to reject invalid context SSH key-source flag" >&2
  exit 1
fi
grep -F "remote E2E report context ssh_authorized_key_set must be yes or no: maybe" "$WORK/trent-close-bad-context-key-flag.out" >/dev/null
test ! -s "$FAKE_CURL_LOG"

MISSING_PREPARE_KEY_CLOSE_REPORT="$WORK/missing-prepare-key-close-report"
cp -R "$TRENT_REPORT" "$MISSING_PREPARE_KEY_CLOSE_REPORT"
sed 's/^ssh_authorized_key_set=no$/ssh_authorized_key_set=yes/' "$TRENT_REPORT/context.txt" >"$MISSING_PREPARE_KEY_CLOSE_REPORT/context.txt"
: >"$FAKE_CURL_LOG"
if CODEXDOCK_FAKE_CURL_LOG="$FAKE_CURL_LOG" \
  CODEXDOCK_FAKE_CURL_BODY="$FAKE_CURL_BODY" \
  CODEXDOCK_TRENT_TOKEN=test-token \
  CODEXDOCK_TRENT_BASE_URL=https://trent.example \
  PATH="$FAKE_BIN:$PATH" \
  "$ROOT/scripts/trent-close-roadmap.sh" "$MISSING_PREPARE_KEY_CLOSE_REPORT" >"$WORK/trent-close-missing-prepare-key.out" 2>&1; then
  echo "expected TrentPlatform roadmap closure to reject prepare command artifacts without the reported SSH key" >&2
  exit 1
fi
grep -F "remote E2E report command artifact does not contain expected token: prepare.cmd --ssh-authorized-key" "$WORK/trent-close-missing-prepare-key.out" >/dev/null
test ! -s "$FAKE_CURL_LOG"

EMPTY_CMD_CLOSE_REPORT="$WORK/empty-cmd-close-report"
cp -R "$TRENT_REPORT" "$EMPTY_CMD_CLOSE_REPORT"
: >"$EMPTY_CMD_CLOSE_REPORT/start.cmd"
: >"$FAKE_CURL_LOG"
if CODEXDOCK_FAKE_CURL_LOG="$FAKE_CURL_LOG" \
  CODEXDOCK_FAKE_CURL_BODY="$FAKE_CURL_BODY" \
  CODEXDOCK_TRENT_TOKEN=test-token \
  CODEXDOCK_TRENT_BASE_URL=https://trent.example \
  PATH="$FAKE_BIN:$PATH" \
  "$ROOT/scripts/trent-close-roadmap.sh" "$EMPTY_CMD_CLOSE_REPORT" >"$WORK/trent-close-empty-cmd.out" 2>&1; then
  echo "expected TrentPlatform roadmap closure to reject empty command artifacts" >&2
  exit 1
fi
grep -F "remote E2E report command artifact is empty: start.cmd" "$WORK/trent-close-empty-cmd.out" >/dev/null
test ! -s "$FAKE_CURL_LOG"

WRONG_CMD_CLOSE_REPORT="$WORK/wrong-cmd-close-report"
cp -R "$TRENT_REPORT" "$WRONG_CMD_CLOSE_REPORT"
printf 'env HOME=/tmp/codexdock /tmp/codexdock sessions homepc\n' >"$WRONG_CMD_CLOSE_REPORT/start.cmd"
: >"$FAKE_CURL_LOG"
if CODEXDOCK_FAKE_CURL_LOG="$FAKE_CURL_LOG" \
  CODEXDOCK_FAKE_CURL_BODY="$FAKE_CURL_BODY" \
  CODEXDOCK_TRENT_TOKEN=test-token \
  CODEXDOCK_TRENT_BASE_URL=https://trent.example \
  PATH="$FAKE_BIN:$PATH" \
  "$ROOT/scripts/trent-close-roadmap.sh" "$WRONG_CMD_CLOSE_REPORT" >"$WORK/trent-close-wrong-cmd.out" 2>&1; then
  echo "expected TrentPlatform roadmap closure to reject wrong command artifacts" >&2
  exit 1
fi
grep -F "remote E2E report command artifact does not contain expected token: start.cmd start" "$WORK/trent-close-wrong-cmd.out" >/dev/null
test ! -s "$FAKE_CURL_LOG"

WRONG_CMD_TARGET_CLOSE_REPORT="$WORK/wrong-cmd-target-close-report"
cp -R "$TRENT_REPORT" "$WRONG_CMD_TARGET_CLOSE_REPORT"
printf 'env HOME=/tmp/codexdock /tmp/codexdock start otherpc\n' >"$WRONG_CMD_TARGET_CLOSE_REPORT/start.cmd"
: >"$FAKE_CURL_LOG"
if CODEXDOCK_FAKE_CURL_LOG="$FAKE_CURL_LOG" \
  CODEXDOCK_FAKE_CURL_BODY="$FAKE_CURL_BODY" \
  CODEXDOCK_TRENT_TOKEN=test-token \
  CODEXDOCK_TRENT_BASE_URL=https://trent.example \
  PATH="$FAKE_BIN:$PATH" \
  "$ROOT/scripts/trent-close-roadmap.sh" "$WRONG_CMD_TARGET_CLOSE_REPORT" >"$WORK/trent-close-wrong-cmd-target.out" 2>&1; then
  echo "expected TrentPlatform roadmap closure to reject command artifacts for the wrong machine" >&2
  exit 1
fi
grep -F "remote E2E report command artifact does not contain expected token: start.cmd homepc" "$WORK/trent-close-wrong-cmd-target.out" >/dev/null
test ! -s "$FAKE_CURL_LOG"

WRONG_LOG_LINES_CMD_CLOSE_REPORT="$WORK/wrong-log-lines-cmd-close-report"
cp -R "$TRENT_REPORT" "$WRONG_LOG_LINES_CMD_CLOSE_REPORT"
printf 'env HOME=/tmp/codexdock /tmp/codexdock logs homepc --lines 99\n' >"$WRONG_LOG_LINES_CMD_CLOSE_REPORT/logs.cmd"
: >"$FAKE_CURL_LOG"
if CODEXDOCK_FAKE_CURL_LOG="$FAKE_CURL_LOG" \
  CODEXDOCK_FAKE_CURL_BODY="$FAKE_CURL_BODY" \
  CODEXDOCK_TRENT_TOKEN=test-token \
  CODEXDOCK_TRENT_BASE_URL=https://trent.example \
  PATH="$FAKE_BIN:$PATH" \
  "$ROOT/scripts/trent-close-roadmap.sh" "$WRONG_LOG_LINES_CMD_CLOSE_REPORT" >"$WORK/trent-close-wrong-log-lines-cmd.out" 2>&1; then
  echo "expected TrentPlatform roadmap closure to reject logs command artifacts with the wrong line count" >&2
  exit 1
fi
grep -F "remote E2E report command artifact did not contain expected text: logs.cmd" "$WORK/trent-close-wrong-log-lines-cmd.out" >/dev/null
test ! -s "$FAKE_CURL_LOG"

WRONG_PROMPT_CMD_CLOSE_REPORT="$WORK/wrong-prompt-cmd-close-report"
cp -R "$TRENT_REPORT" "$WRONG_PROMPT_CMD_CLOSE_REPORT"
printf 'env HOME=/tmp/codexdock /tmp/codexdock send homepc different prompt\n' >"$WRONG_PROMPT_CMD_CLOSE_REPORT/send.cmd"
: >"$FAKE_CURL_LOG"
if CODEXDOCK_FAKE_CURL_LOG="$FAKE_CURL_LOG" \
  CODEXDOCK_FAKE_CURL_BODY="$FAKE_CURL_BODY" \
  CODEXDOCK_TRENT_TOKEN=test-token \
  CODEXDOCK_TRENT_BASE_URL=https://trent.example \
  PATH="$FAKE_BIN:$PATH" \
  "$ROOT/scripts/trent-close-roadmap.sh" "$WRONG_PROMPT_CMD_CLOSE_REPORT" >"$WORK/trent-close-wrong-prompt-cmd.out" 2>&1; then
  echo "expected TrentPlatform roadmap closure to reject send command artifacts with the wrong prompt" >&2
  exit 1
fi
grep -F "remote E2E report command artifact did not contain expected text: send.cmd" "$WORK/trent-close-wrong-prompt-cmd.out" >/dev/null
test ! -s "$FAKE_CURL_LOG"

WRONG_SETUP_SESSION_CMD_CLOSE_REPORT="$WORK/wrong-setup-session-cmd-close-report"
cp -R "$TRENT_REPORT" "$WRONG_SETUP_SESSION_CMD_CLOSE_REPORT"
sed 's/--session codexdock-e2e/--session other-session/' "$TRENT_REPORT/init.cmd" >"$WRONG_SETUP_SESSION_CMD_CLOSE_REPORT/init.cmd"
: >"$FAKE_CURL_LOG"
if CODEXDOCK_FAKE_CURL_LOG="$FAKE_CURL_LOG" \
  CODEXDOCK_FAKE_CURL_BODY="$FAKE_CURL_BODY" \
  CODEXDOCK_TRENT_TOKEN=test-token \
  CODEXDOCK_TRENT_BASE_URL=https://trent.example \
  PATH="$FAKE_BIN:$PATH" \
  "$ROOT/scripts/trent-close-roadmap.sh" "$WRONG_SETUP_SESSION_CMD_CLOSE_REPORT" >"$WORK/trent-close-wrong-setup-session-cmd.out" 2>&1; then
  echo "expected TrentPlatform roadmap closure to reject setup command artifacts with the wrong session" >&2
  exit 1
fi
grep -F "remote E2E report command artifact did not contain expected text: init.cmd" "$WORK/trent-close-wrong-setup-session-cmd.out" >/dev/null
test ! -s "$FAKE_CURL_LOG"

WRONG_SETUP_WORKSPACE_CMD_CLOSE_REPORT="$WORK/wrong-setup-workspace-cmd-close-report"
cp -R "$TRENT_REPORT" "$WRONG_SETUP_WORKSPACE_CMD_CLOSE_REPORT"
sed 's|--workspace ~/code|--workspace ~/other|' "$TRENT_REPORT/init.cmd" >"$WRONG_SETUP_WORKSPACE_CMD_CLOSE_REPORT/init.cmd"
: >"$FAKE_CURL_LOG"
if CODEXDOCK_FAKE_CURL_LOG="$FAKE_CURL_LOG" \
  CODEXDOCK_FAKE_CURL_BODY="$FAKE_CURL_BODY" \
  CODEXDOCK_TRENT_TOKEN=test-token \
  CODEXDOCK_TRENT_BASE_URL=https://trent.example \
  PATH="$FAKE_BIN:$PATH" \
  "$ROOT/scripts/trent-close-roadmap.sh" "$WRONG_SETUP_WORKSPACE_CMD_CLOSE_REPORT" >"$WORK/trent-close-wrong-setup-workspace-cmd.out" 2>&1; then
  echo "expected TrentPlatform roadmap closure to reject setup command artifacts with the wrong workspace" >&2
  exit 1
fi
grep -F "remote E2E report command artifact did not contain expected text: init.cmd" "$WORK/trent-close-wrong-setup-workspace-cmd.out" >/dev/null
test ! -s "$FAKE_CURL_LOG"

WRONG_SETUP_AGENT_CMD_CLOSE_REPORT="$WORK/wrong-setup-agent-cmd-close-report"
cp -R "$TRENT_REPORT" "$WRONG_SETUP_AGENT_CMD_CLOSE_REPORT"
sed 's/--agent codex/--agent other-agent/' "$TRENT_REPORT/init.cmd" >"$WRONG_SETUP_AGENT_CMD_CLOSE_REPORT/init.cmd"
: >"$FAKE_CURL_LOG"
if CODEXDOCK_FAKE_CURL_LOG="$FAKE_CURL_LOG" \
  CODEXDOCK_FAKE_CURL_BODY="$FAKE_CURL_BODY" \
  CODEXDOCK_TRENT_TOKEN=test-token \
  CODEXDOCK_TRENT_BASE_URL=https://trent.example \
  PATH="$FAKE_BIN:$PATH" \
  "$ROOT/scripts/trent-close-roadmap.sh" "$WRONG_SETUP_AGENT_CMD_CLOSE_REPORT" >"$WORK/trent-close-wrong-setup-agent-cmd.out" 2>&1; then
  echo "expected TrentPlatform roadmap closure to reject setup command artifacts with the wrong agent" >&2
  exit 1
fi
grep -F "remote E2E report command artifact did not contain expected text: init.cmd" "$WORK/trent-close-wrong-setup-agent-cmd.out" >/dev/null
test ! -s "$FAKE_CURL_LOG"

WRONG_INIT_NETWORK_CMD_CLOSE_REPORT="$WORK/wrong-init-network-cmd-close-report"
cp -R "$TRENT_REPORT" "$WRONG_INIT_NETWORK_CMD_CLOSE_REPORT"
sed 's/--network personal/--network other-network/' "$TRENT_REPORT/init.cmd" >"$WRONG_INIT_NETWORK_CMD_CLOSE_REPORT/init.cmd"
: >"$FAKE_CURL_LOG"
if CODEXDOCK_FAKE_CURL_LOG="$FAKE_CURL_LOG" \
  CODEXDOCK_FAKE_CURL_BODY="$FAKE_CURL_BODY" \
  CODEXDOCK_TRENT_TOKEN=test-token \
  CODEXDOCK_TRENT_BASE_URL=https://trent.example \
  PATH="$FAKE_BIN:$PATH" \
  "$ROOT/scripts/trent-close-roadmap.sh" "$WRONG_INIT_NETWORK_CMD_CLOSE_REPORT" >"$WORK/trent-close-wrong-init-network-cmd.out" 2>&1; then
  echo "expected TrentPlatform roadmap closure to reject init command artifacts with the wrong network" >&2
  exit 1
fi
grep -F "remote E2E report command artifact did not contain expected text: init.cmd" "$WORK/trent-close-wrong-init-network-cmd.out" >/dev/null
test ! -s "$FAKE_CURL_LOG"

WRONG_INIT_HOST_CMD_CLOSE_REPORT="$WORK/wrong-init-host-cmd-close-report"
cp -R "$TRENT_REPORT" "$WRONG_INIT_HOST_CMD_CLOSE_REPORT"
sed 's/--host 100.64.0.2/--host 100.64.0.99/' "$TRENT_REPORT/init.cmd" >"$WRONG_INIT_HOST_CMD_CLOSE_REPORT/init.cmd"
: >"$FAKE_CURL_LOG"
if CODEXDOCK_FAKE_CURL_LOG="$FAKE_CURL_LOG" \
  CODEXDOCK_FAKE_CURL_BODY="$FAKE_CURL_BODY" \
  CODEXDOCK_TRENT_TOKEN=test-token \
  CODEXDOCK_TRENT_BASE_URL=https://trent.example \
  PATH="$FAKE_BIN:$PATH" \
  "$ROOT/scripts/trent-close-roadmap.sh" "$WRONG_INIT_HOST_CMD_CLOSE_REPORT" >"$WORK/trent-close-wrong-init-host-cmd.out" 2>&1; then
  echo "expected TrentPlatform roadmap closure to reject init command artifacts with the wrong host" >&2
  exit 1
fi
grep -F "remote E2E report command artifact did not contain expected text: init.cmd" "$WORK/trent-close-wrong-init-host-cmd.out" >/dev/null
test ! -s "$FAKE_CURL_LOG"

WRONG_INIT_USER_CMD_CLOSE_REPORT="$WORK/wrong-init-user-cmd-close-report"
cp -R "$TRENT_REPORT" "$WRONG_INIT_USER_CMD_CLOSE_REPORT"
sed 's/--ssh-user manoj/--ssh-user other-user/' "$TRENT_REPORT/init.cmd" >"$WRONG_INIT_USER_CMD_CLOSE_REPORT/init.cmd"
: >"$FAKE_CURL_LOG"
if CODEXDOCK_FAKE_CURL_LOG="$FAKE_CURL_LOG" \
  CODEXDOCK_FAKE_CURL_BODY="$FAKE_CURL_BODY" \
  CODEXDOCK_TRENT_TOKEN=test-token \
  CODEXDOCK_TRENT_BASE_URL=https://trent.example \
  PATH="$FAKE_BIN:$PATH" \
  "$ROOT/scripts/trent-close-roadmap.sh" "$WRONG_INIT_USER_CMD_CLOSE_REPORT" >"$WORK/trent-close-wrong-init-user-cmd.out" 2>&1; then
  echo "expected TrentPlatform roadmap closure to reject init command artifacts with the wrong SSH user" >&2
  exit 1
fi
grep -F "remote E2E report command artifact did not contain expected text: init.cmd" "$WORK/trent-close-wrong-init-user-cmd.out" >/dev/null
test ! -s "$FAKE_CURL_LOG"

WRONG_INIT_PORT_CMD_CLOSE_REPORT="$WORK/wrong-init-port-cmd-close-report"
cp -R "$TRENT_REPORT" "$WRONG_INIT_PORT_CMD_CLOSE_REPORT"
sed 's/--ssh-port 22/--ssh-port 2222/' "$TRENT_REPORT/init.cmd" >"$WRONG_INIT_PORT_CMD_CLOSE_REPORT/init.cmd"
: >"$FAKE_CURL_LOG"
if CODEXDOCK_FAKE_CURL_LOG="$FAKE_CURL_LOG" \
  CODEXDOCK_FAKE_CURL_BODY="$FAKE_CURL_BODY" \
  CODEXDOCK_TRENT_TOKEN=test-token \
  CODEXDOCK_TRENT_BASE_URL=https://trent.example \
  PATH="$FAKE_BIN:$PATH" \
  "$ROOT/scripts/trent-close-roadmap.sh" "$WRONG_INIT_PORT_CMD_CLOSE_REPORT" >"$WORK/trent-close-wrong-init-port-cmd.out" 2>&1; then
  echo "expected TrentPlatform roadmap closure to reject init command artifacts with the wrong SSH port" >&2
  exit 1
fi
grep -F "remote E2E report command artifact did not contain expected text: init.cmd" "$WORK/trent-close-wrong-init-port-cmd.out" >/dev/null
test ! -s "$FAKE_CURL_LOG"

WRONG_INIT_CONTROL_URL_CMD_CLOSE_REPORT="$WORK/wrong-init-control-url-cmd-close-report"
cp -R "$TRENT_REPORT" "$WRONG_INIT_CONTROL_URL_CMD_CLOSE_REPORT"
sed 's|^control_url=$|control_url=https://control.example|' "$TRENT_REPORT/context.txt" >"$WRONG_INIT_CONTROL_URL_CMD_CLOSE_REPORT/context.txt"
: >"$FAKE_CURL_LOG"
if CODEXDOCK_FAKE_CURL_LOG="$FAKE_CURL_LOG" \
  CODEXDOCK_FAKE_CURL_BODY="$FAKE_CURL_BODY" \
  CODEXDOCK_TRENT_TOKEN=test-token \
  CODEXDOCK_TRENT_BASE_URL=https://trent.example \
  PATH="$FAKE_BIN:$PATH" \
  "$ROOT/scripts/trent-close-roadmap.sh" "$WRONG_INIT_CONTROL_URL_CMD_CLOSE_REPORT" >"$WORK/trent-close-wrong-init-control-url-cmd.out" 2>&1; then
  echo "expected TrentPlatform roadmap closure to reject init command artifacts missing the reported control URL" >&2
  exit 1
fi
grep -F "remote E2E report command artifact did not contain expected text: init.cmd" "$WORK/trent-close-wrong-init-control-url-cmd.out" >/dev/null
test ! -s "$FAKE_CURL_LOG"

WRONG_CREATE_NETWORK_CMD_CLOSE_REPORT="$WORK/wrong-create-network-cmd-close-report"
cp -R "$TRENT_REPORT" "$WRONG_CREATE_NETWORK_CMD_CLOSE_REPORT"
mv "$WRONG_CREATE_NETWORK_CMD_CLOSE_REPORT/init.cmd" "$WRONG_CREATE_NETWORK_CMD_CLOSE_REPORT/init.cmd.bak"
mv "$WRONG_CREATE_NETWORK_CMD_CLOSE_REPORT/init.out" "$WRONG_CREATE_NETWORK_CMD_CLOSE_REPORT/init.out.bak"
mv "$WRONG_CREATE_NETWORK_CMD_CLOSE_REPORT/init.err" "$WRONG_CREATE_NETWORK_CMD_CLOSE_REPORT/init.err.bak"
sed 's/^adopt=0$/adopt=1/' "$TRENT_REPORT/context.txt" >"$WRONG_CREATE_NETWORK_CMD_CLOSE_REPORT/context.txt"
cat >"$WRONG_CREATE_NETWORK_CMD_CLOSE_REPORT/create.cmd" <<'EOF'
env HOME=/tmp/codexdock-home /tmp/codexdock create other-network
EOF
printf 'created network\n' >"$WRONG_CREATE_NETWORK_CMD_CLOSE_REPORT/create.out"
: >"$WRONG_CREATE_NETWORK_CMD_CLOSE_REPORT/create.err"
cat >"$WRONG_CREATE_NETWORK_CMD_CLOSE_REPORT/adopt.cmd" <<'EOF'
env HOME=/tmp/codexdock-home /tmp/codexdock adopt homepc --ssh-user manoj --ssh-port 22 --workspace ~/code --session codexdock-e2e --agent codex
EOF
printf 'adopted machine\n' >"$WRONG_CREATE_NETWORK_CMD_CLOSE_REPORT/adopt.out"
: >"$WRONG_CREATE_NETWORK_CMD_CLOSE_REPORT/adopt.err"
: >"$FAKE_CURL_LOG"
if CODEXDOCK_FAKE_CURL_LOG="$FAKE_CURL_LOG" \
  CODEXDOCK_FAKE_CURL_BODY="$FAKE_CURL_BODY" \
  CODEXDOCK_TRENT_TOKEN=test-token \
  CODEXDOCK_TRENT_BASE_URL=https://trent.example \
  PATH="$FAKE_BIN:$PATH" \
  "$ROOT/scripts/trent-close-roadmap.sh" "$WRONG_CREATE_NETWORK_CMD_CLOSE_REPORT" >"$WORK/trent-close-wrong-create-network-cmd.out" 2>&1; then
  echo "expected TrentPlatform roadmap closure to reject create command artifacts with the wrong network" >&2
  exit 1
fi
grep -F "remote E2E report command artifact did not contain expected text: create.cmd" "$WORK/trent-close-wrong-create-network-cmd.out" >/dev/null
test ! -s "$FAKE_CURL_LOG"

WRONG_CREATE_CONTROL_URL_CMD_CLOSE_REPORT="$WORK/wrong-create-control-url-cmd-close-report"
cp -R "$TRENT_REPORT" "$WRONG_CREATE_CONTROL_URL_CMD_CLOSE_REPORT"
mv "$WRONG_CREATE_CONTROL_URL_CMD_CLOSE_REPORT/init.cmd" "$WRONG_CREATE_CONTROL_URL_CMD_CLOSE_REPORT/init.cmd.bak"
mv "$WRONG_CREATE_CONTROL_URL_CMD_CLOSE_REPORT/init.out" "$WRONG_CREATE_CONTROL_URL_CMD_CLOSE_REPORT/init.out.bak"
mv "$WRONG_CREATE_CONTROL_URL_CMD_CLOSE_REPORT/init.err" "$WRONG_CREATE_CONTROL_URL_CMD_CLOSE_REPORT/init.err.bak"
sed -e 's/^adopt=0$/adopt=1/' -e 's|^control_url=$|control_url=https://control.example|' "$TRENT_REPORT/context.txt" >"$WRONG_CREATE_CONTROL_URL_CMD_CLOSE_REPORT/context.txt"
cat >"$WRONG_CREATE_CONTROL_URL_CMD_CLOSE_REPORT/create.cmd" <<'EOF'
env HOME=/tmp/codexdock-home /tmp/codexdock create personal
EOF
printf 'created network\n' >"$WRONG_CREATE_CONTROL_URL_CMD_CLOSE_REPORT/create.out"
: >"$WRONG_CREATE_CONTROL_URL_CMD_CLOSE_REPORT/create.err"
cat >"$WRONG_CREATE_CONTROL_URL_CMD_CLOSE_REPORT/adopt.cmd" <<'EOF'
env HOME=/tmp/codexdock-home /tmp/codexdock adopt homepc --ssh-user manoj --ssh-port 22 --workspace ~/code --session codexdock-e2e --agent codex
EOF
printf 'adopted machine\n' >"$WRONG_CREATE_CONTROL_URL_CMD_CLOSE_REPORT/adopt.out"
: >"$WRONG_CREATE_CONTROL_URL_CMD_CLOSE_REPORT/adopt.err"
: >"$FAKE_CURL_LOG"
if CODEXDOCK_FAKE_CURL_LOG="$FAKE_CURL_LOG" \
  CODEXDOCK_FAKE_CURL_BODY="$FAKE_CURL_BODY" \
  CODEXDOCK_TRENT_TOKEN=test-token \
  CODEXDOCK_TRENT_BASE_URL=https://trent.example \
  PATH="$FAKE_BIN:$PATH" \
  "$ROOT/scripts/trent-close-roadmap.sh" "$WRONG_CREATE_CONTROL_URL_CMD_CLOSE_REPORT" >"$WORK/trent-close-wrong-create-control-url-cmd.out" 2>&1; then
  echo "expected TrentPlatform roadmap closure to reject create command artifacts missing the reported control URL" >&2
  exit 1
fi
grep -F "remote E2E report command artifact did not contain expected text: create.cmd" "$WORK/trent-close-wrong-create-control-url-cmd.out" >/dev/null
test ! -s "$FAKE_CURL_LOG"

WRONG_ADOPT_USER_CMD_CLOSE_REPORT="$WORK/wrong-adopt-user-cmd-close-report"
cp -R "$TRENT_REPORT" "$WRONG_ADOPT_USER_CMD_CLOSE_REPORT"
mv "$WRONG_ADOPT_USER_CMD_CLOSE_REPORT/init.cmd" "$WRONG_ADOPT_USER_CMD_CLOSE_REPORT/init.cmd.bak"
mv "$WRONG_ADOPT_USER_CMD_CLOSE_REPORT/init.out" "$WRONG_ADOPT_USER_CMD_CLOSE_REPORT/init.out.bak"
mv "$WRONG_ADOPT_USER_CMD_CLOSE_REPORT/init.err" "$WRONG_ADOPT_USER_CMD_CLOSE_REPORT/init.err.bak"
sed 's/^adopt=0$/adopt=1/' "$TRENT_REPORT/context.txt" >"$WRONG_ADOPT_USER_CMD_CLOSE_REPORT/context.txt"
cat >"$WRONG_ADOPT_USER_CMD_CLOSE_REPORT/create.cmd" <<'EOF'
env HOME=/tmp/codexdock-home /tmp/codexdock create personal
EOF
printf 'created network\n' >"$WRONG_ADOPT_USER_CMD_CLOSE_REPORT/create.out"
: >"$WRONG_ADOPT_USER_CMD_CLOSE_REPORT/create.err"
cat >"$WRONG_ADOPT_USER_CMD_CLOSE_REPORT/adopt.cmd" <<'EOF'
env HOME=/tmp/codexdock-home /tmp/codexdock adopt homepc --ssh-user other-user --ssh-port 22 --workspace ~/code --session codexdock-e2e --agent codex
EOF
printf 'adopted machine\n' >"$WRONG_ADOPT_USER_CMD_CLOSE_REPORT/adopt.out"
: >"$WRONG_ADOPT_USER_CMD_CLOSE_REPORT/adopt.err"
: >"$FAKE_CURL_LOG"
if CODEXDOCK_FAKE_CURL_LOG="$FAKE_CURL_LOG" \
  CODEXDOCK_FAKE_CURL_BODY="$FAKE_CURL_BODY" \
  CODEXDOCK_TRENT_TOKEN=test-token \
  CODEXDOCK_TRENT_BASE_URL=https://trent.example \
  PATH="$FAKE_BIN:$PATH" \
  "$ROOT/scripts/trent-close-roadmap.sh" "$WRONG_ADOPT_USER_CMD_CLOSE_REPORT" >"$WORK/trent-close-wrong-adopt-user-cmd.out" 2>&1; then
  echo "expected TrentPlatform roadmap closure to reject adopt command artifacts with the wrong SSH user" >&2
  exit 1
fi
grep -F "remote E2E report command artifact did not contain expected text: adopt.cmd" "$WORK/trent-close-wrong-adopt-user-cmd.out" >/dev/null
test ! -s "$FAKE_CURL_LOG"

WRONG_ADOPT_PORT_CMD_CLOSE_REPORT="$WORK/wrong-adopt-port-cmd-close-report"
cp -R "$TRENT_REPORT" "$WRONG_ADOPT_PORT_CMD_CLOSE_REPORT"
mv "$WRONG_ADOPT_PORT_CMD_CLOSE_REPORT/init.cmd" "$WRONG_ADOPT_PORT_CMD_CLOSE_REPORT/init.cmd.bak"
mv "$WRONG_ADOPT_PORT_CMD_CLOSE_REPORT/init.out" "$WRONG_ADOPT_PORT_CMD_CLOSE_REPORT/init.out.bak"
mv "$WRONG_ADOPT_PORT_CMD_CLOSE_REPORT/init.err" "$WRONG_ADOPT_PORT_CMD_CLOSE_REPORT/init.err.bak"
sed 's/^adopt=0$/adopt=1/' "$TRENT_REPORT/context.txt" >"$WRONG_ADOPT_PORT_CMD_CLOSE_REPORT/context.txt"
cat >"$WRONG_ADOPT_PORT_CMD_CLOSE_REPORT/create.cmd" <<'EOF'
env HOME=/tmp/codexdock-home /tmp/codexdock create personal
EOF
printf 'created network\n' >"$WRONG_ADOPT_PORT_CMD_CLOSE_REPORT/create.out"
: >"$WRONG_ADOPT_PORT_CMD_CLOSE_REPORT/create.err"
cat >"$WRONG_ADOPT_PORT_CMD_CLOSE_REPORT/adopt.cmd" <<'EOF'
env HOME=/tmp/codexdock-home /tmp/codexdock adopt homepc --ssh-user manoj --ssh-port 2222 --workspace ~/code --session codexdock-e2e --agent codex
EOF
printf 'adopted machine\n' >"$WRONG_ADOPT_PORT_CMD_CLOSE_REPORT/adopt.out"
: >"$WRONG_ADOPT_PORT_CMD_CLOSE_REPORT/adopt.err"
: >"$FAKE_CURL_LOG"
if CODEXDOCK_FAKE_CURL_LOG="$FAKE_CURL_LOG" \
  CODEXDOCK_FAKE_CURL_BODY="$FAKE_CURL_BODY" \
  CODEXDOCK_TRENT_TOKEN=test-token \
  CODEXDOCK_TRENT_BASE_URL=https://trent.example \
  PATH="$FAKE_BIN:$PATH" \
  "$ROOT/scripts/trent-close-roadmap.sh" "$WRONG_ADOPT_PORT_CMD_CLOSE_REPORT" >"$WORK/trent-close-wrong-adopt-port-cmd.out" 2>&1; then
  echo "expected TrentPlatform roadmap closure to reject adopt command artifacts with the wrong SSH port" >&2
  exit 1
fi
grep -F "remote E2E report command artifact did not contain expected text: adopt.cmd" "$WORK/trent-close-wrong-adopt-port-cmd.out" >/dev/null
test ! -s "$FAKE_CURL_LOG"

BAD_CONTENT_CLOSE_REPORT="$WORK/bad-content-close-report"
cp -R "$TRENT_REPORT" "$BAD_CONTENT_CLOSE_REPORT"
printf 'doctor output without readiness checks\n' >"$BAD_CONTENT_CLOSE_REPORT/doctor.out"
: >"$FAKE_CURL_LOG"
if CODEXDOCK_FAKE_CURL_LOG="$FAKE_CURL_LOG" \
  CODEXDOCK_FAKE_CURL_BODY="$FAKE_CURL_BODY" \
  CODEXDOCK_TRENT_TOKEN=test-token \
  CODEXDOCK_TRENT_BASE_URL=https://trent.example \
  PATH="$FAKE_BIN:$PATH" \
  "$ROOT/scripts/trent-close-roadmap.sh" "$BAD_CONTENT_CLOSE_REPORT" >"$WORK/trent-close-bad-content.out" 2>&1; then
  echo "expected TrentPlatform roadmap closure to reject reports with missing success output" >&2
  exit 1
fi
grep -F "remote E2E report artifact did not contain expected text: doctor.out" "$WORK/trent-close-bad-content.out" >/dev/null
test ! -s "$FAKE_CURL_LOG"

: >"$FAKE_CURL_LOG"
if CODEXDOCK_FAKE_CURL_LOG="$FAKE_CURL_LOG" \
  CODEXDOCK_FAKE_CURL_BODY="$FAKE_CURL_BODY" \
  CODEXDOCK_TRENT_TOKEN=test-token \
  CODEXDOCK_TRENT_PROJECT=111764 \
  CODEXDOCK_TRENT_BASE_URL=https://trent.example \
  PATH="$FAKE_BIN:$PATH" \
  "$ROOT/scripts/trent-finalize-e2e.sh" "$BAD_CONTENT_CLOSE_REPORT" >"$WORK/trent-finalize-bad-content.out" 2>&1; then
  echo "expected TrentPlatform finalization to reject reports with missing success output" >&2
  exit 1
fi
grep -F "remote E2E report artifact did not contain expected text: doctor.out" "$WORK/trent-finalize-bad-content.out" >/dev/null
test ! -s "$FAKE_CURL_LOG"

INCOMPLETE_CLOSE_REPORT="$WORK/incomplete-close-report"
mkdir -p "$INCOMPLETE_CLOSE_REPORT"
cat >"$INCOMPLETE_CLOSE_REPORT/result.txt" <<'EOF'
status=success
exit_code=0
network=personal
machine=homepc
session=codexdock-e2e
session_started=yes
session_stopped=yes
cleanup_attempted=no
cleanup_exit_code=not_applicable
EOF
: >"$FAKE_CURL_LOG"
if CODEXDOCK_FAKE_CURL_LOG="$FAKE_CURL_LOG" \
  CODEXDOCK_FAKE_CURL_BODY="$FAKE_CURL_BODY" \
  CODEXDOCK_TRENT_TOKEN=test-token \
  CODEXDOCK_TRENT_BASE_URL=https://trent.example \
  PATH="$FAKE_BIN:$PATH" \
  "$ROOT/scripts/trent-close-roadmap.sh" "$INCOMPLETE_CLOSE_REPORT" >"$WORK/trent-close-incomplete.out" 2>&1; then
  echo "expected TrentPlatform roadmap closure to reject incomplete success reports" >&2
  exit 1
fi
grep -F "remote E2E report is missing required artifact" "$WORK/trent-close-incomplete.out" >/dev/null
test ! -s "$FAKE_CURL_LOG"

FAILED_CLOSE_REPORT="$WORK/failed-close-report"
mkdir -p "$FAILED_CLOSE_REPORT"
cat >"$FAILED_CLOSE_REPORT/result.txt" <<'EOF'
status=failure
exit_code=1
network=personal
machine=homepc
session=codexdock-e2e
EOF
: >"$FAKE_CURL_LOG"
if CODEXDOCK_FAKE_CURL_LOG="$FAKE_CURL_LOG" \
  CODEXDOCK_FAKE_CURL_BODY="$FAKE_CURL_BODY" \
  CODEXDOCK_TRENT_TOKEN=test-token \
  CODEXDOCK_TRENT_BASE_URL=https://trent.example \
  PATH="$FAKE_BIN:$PATH" \
  "$ROOT/scripts/trent-close-roadmap.sh" "$FAILED_CLOSE_REPORT" >"$WORK/trent-close-failed.out" 2>&1; then
  echo "expected TrentPlatform roadmap closure to reject failed E2E reports" >&2
  exit 1
fi
grep -F "remote E2E report is not successful" "$WORK/trent-close-failed.out" >/dev/null
test ! -s "$FAKE_CURL_LOG"

"$ROOT/scripts/e2e-local-sim.sh" >"$WORK/e2e-local-sim.out"
grep -F "local simulated e2e ok" "$WORK/e2e-local-sim.out" >/dev/null

if "$ROOT/scripts/e2e-remote.sh" >"$WORK/e2e-missing.out" 2>&1; then
  echo "expected remote E2E harness to require CODEXDOCK_HOST" >&2
  exit 1
fi
grep -F "CODEXDOCK_HOST is required" "$WORK/e2e-missing.out" >/dev/null

BAD_FLAGS_RUN_REPORT="$WORK/e2e-run-bad-flags"
if CODEXDOCK_REPORT_DIR="$BAD_FLAGS_RUN_REPORT" \
  CODEXDOCK_ADOPT=maybe \
  CODEXDOCK_USER=manoj \
  "$ROOT/scripts/e2e-remote.sh" >"$WORK/e2e-run-bad-flags.out" 2>&1; then
  echo "expected remote E2E harness to reject invalid flag values" >&2
  exit 1
fi
grep -F "CODEXDOCK_ADOPT must be 0 or 1" "$WORK/e2e-run-bad-flags.out" >/dev/null
test ! -e "$BAD_FLAGS_RUN_REPORT/result.txt"
test ! -e "$BAD_FLAGS_RUN_REPORT/context.txt"

BAD_ARCH_RUN_REPORT="$WORK/e2e-run-bad-arch"
if CODEXDOCK_REPORT_DIR="$BAD_ARCH_RUN_REPORT" \
  CODEXDOCK_HOST=100.64.0.2 \
  CODEXDOCK_USER=manoj \
  CODEXDOCK_TARGET_ARCH=mips \
  "$ROOT/scripts/e2e-remote.sh" >"$WORK/e2e-run-bad-arch.out" 2>&1; then
  echo "expected remote E2E harness to reject unsupported target architecture" >&2
  exit 1
fi
grep -F "unsupported CODEXDOCK_TARGET_ARCH: mips" "$WORK/e2e-run-bad-arch.out" >/dev/null
test ! -e "$BAD_ARCH_RUN_REPORT/result.txt"
test ! -e "$BAD_ARCH_RUN_REPORT/context.txt"

printf 'smoke ok\n'
