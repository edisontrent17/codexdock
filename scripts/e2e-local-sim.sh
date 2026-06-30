#!/usr/bin/env sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP=${TMPDIR:-/tmp}
WORK=$(mktemp -d "$TMP/codexdock-local-e2e.XXXXXX")
cleanup() {
  rm -rf "$WORK"
}
trap cleanup EXIT INT TERM

BIN="$WORK/codexdock"
HOME_DIR="$WORK/home"
JOIN_HOME_DIR="$WORK/join-home"
FAKE_BIN="$WORK/bin"
FAKE_LOG="$WORK/fake-tools.log"
FAKE_SESSION_DIR="$WORK/fake-sessions"
DIRECT_SESSION_DIR="$WORK/direct-e2e-sessions"
BIN_MODE_SESSION_DIR="$WORK/bin-mode-e2e-sessions"
mkdir -p "$HOME_DIR" "$JOIN_HOME_DIR" "$FAKE_BIN" "$FAKE_SESSION_DIR" "$DIRECT_SESSION_DIR" "$BIN_MODE_SESSION_DIR"
: >"$FAKE_LOG"

GOCACHE=${GOCACHE:-/tmp/codexdock-gocache}
GOMODCACHE=${GOMODCACHE:-/tmp/codexdock-gomodcache}
VERSION=${VERSION:-local-e2e}
COMMIT=${COMMIT:-local-e2e}
BUILD_DATE=${BUILD_DATE:-1970-01-01T00:00:00Z}

cat >"$FAKE_BIN/headscale" <<'EOF'
#!/usr/bin/env sh
set -eu
printf 'headscale %s\n' "$*" >>"$CODEXDOCK_FAKE_LOG"
if [ "${1:-}" = "users" ] && [ "${2:-}" = "create" ] && [ "${3:-}" = "personal" ]; then
  : >"$CODEXDOCK_FAKE_SESSION_DIR/headscale-personal-user"
  exit 0
fi
if [ "${1:-}" = "users" ] && [ "${2:-}" = "list" ] && [ "${3:-}" = "--name" ] && [ "${4:-}" = "personal" ] && [ "${5:-}" = "--output=json" ]; then
  if [ -f "$CODEXDOCK_FAKE_SESSION_DIR/headscale-personal-user" ]; then
    printf '[{"id":"7","name":"personal"}]\n'
  else
    printf '[]\n'
  fi
  exit 0
fi
if [ "${1:-}" = "preauthkeys" ] && [ "${2:-}" = "create" ]; then
  printf '{"key":"tskey-local"}\n'
  exit 0
fi
printf 'unexpected headscale command: %s\n' "$*" >&2
exit 1
EOF

cat >"$FAKE_BIN/tailscale" <<'EOF'
#!/usr/bin/env sh
set -eu
printf 'tailscale %s\n' "$*" >>"$CODEXDOCK_FAKE_LOG"
if [ "${1:-}" = "status" ] && [ "${2:-}" = "--json" ]; then
  cat <<'JSON'
{"Self":{"HostName":"macbook","TailscaleIPs":["100.64.0.10"],"Online":true},"Peer":{"homepc":{"HostName":"homepc","TailscaleIPs":["100.64.0.2"],"Online":true}}}
JSON
  exit 0
fi
if [ "${1:-}" = "up" ]; then
  exit 0
fi
printf 'unexpected tailscale command: %s\n' "$*" >&2
exit 1
EOF

cat >"$FAKE_BIN/ssh" <<'EOF'
#!/usr/bin/env sh
set -eu
printf 'ssh %s\n' "$*" >>"$CODEXDOCK_FAKE_LOG"
cmd=""
target=""
for arg do
  target=$cmd
  cmd=$arg
done
session_key=$(printf '%s' "$target" | tr -c 'A-Za-z0-9_.-' '_')
session_file="$CODEXDOCK_FAKE_SESSION_DIR/$session_key"
session_from_target() {
  session=${cmd#* -t }
  session=${session%% *}
  printf '%s' "$session"
}
case "$cmd" in
  *@*) exit 0 ;;
  true) exit 0 ;;
  "curl -fsSL https://tailscale.com/install.sh | sh") exit 0 ;;
  "sudo apt update && sudo apt install -y openssh-server && (sudo systemctl enable --now ssh || sudo service ssh start)") exit 0 ;;
  *authorized_keys*) exit 0 ;;
  "sudo apt update && sudo apt install -y tmux") exit 0 ;;
  'mkdir -p "$HOME/code"') exit 0 ;;
  "command -v tmux") printf '/usr/bin/tmux\n'; exit 0 ;;
  "command -v codex") printf '/usr/local/bin/codex\n'; exit 0 ;;
  'test -d $HOME/code') exit 0 ;;
  'test -d $HOME/src') exit 0 ;;
  "tmux ls")
    if test -f "$session_file"; then
      session=$(sed -n '1p' "$session_file")
      printf '%s: 1 windows (created Sun Jun 28 00:00:00 2026)\n' "$session"
      exit 0
    fi
    printf 'no server running on /tmp/tmux-1000/default\n' >&2
    exit 1
    ;;
  "tmux has-session -t "*" 2>/dev/null || tmux new-session -d -s "*)
    session=$(session_from_target)
    printf '%s\n' "$session" >"$session_file"
    exit 0
    ;;
  "tmux has-session -t "*)
    session=$(session_from_target)
    test -f "$session_file" && test "$(sed -n '1p' "$session_file")" = "$session"
    exit $?
    ;;
  "tmux attach -t "*) exit 0 ;;
  "tmux send-keys -t "*)
    session=$(session_from_target)
    test -f "$session_file" && test "$(sed -n '1p' "$session_file")" = "$session"
    exit $?
    ;;
  "tmux capture-pane -t "*)
    session=$(session_from_target)
    if test -f "$session_file" && test "$(sed -n '1p' "$session_file")" = "$session"; then
      printf 'codex simulated log\n'
      exit 0
    fi
    exit 1
    ;;
  "tmux kill-session -t "*)
    session=$(session_from_target)
    if test -f "$session_file" && test "$(sed -n '1p' "$session_file")" = "$session"; then
      if test -f "$CODEXDOCK_FAKE_SESSION_DIR/fail-kill"; then
        printf 'forced kill failure\n' >&2
        exit 1
      fi
      rm -f "$session_file"
      exit 0
    fi
    exit 1
    ;;
esac
printf 'unexpected ssh command: %s\n' "$cmd" >&2
exit 1
EOF

chmod +x "$FAKE_BIN/headscale" "$FAKE_BIN/tailscale" "$FAKE_BIN/ssh"

GOCACHE="$GOCACHE" GOMODCACHE="$GOMODCACHE" VERSION="$VERSION" COMMIT="$COMMIT" BUILD_DATE="$BUILD_DATE" OUT="$BIN" "$ROOT/scripts/build.sh" >/dev/null

PREFLIGHT_REPORT="$WORK/preflight-report"
CODEXDOCK_FAKE_LOG="$FAKE_LOG" \
  CODEXDOCK_FAKE_SESSION_DIR="$FAKE_SESSION_DIR" \
  PATH="$FAKE_BIN:$PATH" \
  CODEXDOCK_HOST=100.64.0.10 \
  CODEXDOCK_USER=manoj \
  CODEXDOCK_REPORT_DIR="$PREFLIGHT_REPORT" \
  "$ROOT/scripts/e2e-remote.sh" --preflight >"$WORK/preflight.out"
grep -F "remote e2e preflight ok" "$WORK/preflight.out" >/dev/null
test -f "$PREFLIGHT_REPORT/preflight.txt"
test -f "$PREFLIGHT_REPORT/result.txt"
grep -F "missing=none" "$PREFLIGHT_REPORT/preflight.txt" >/dev/null
grep -F "local_ssh=yes" "$PREFLIGHT_REPORT/preflight.txt" >/dev/null
grep -F "private_network_client=yes" "$PREFLIGHT_REPORT/preflight.txt" >/dev/null
grep -F "status=success" "$PREFLIGHT_REPORT/result.txt" >/dev/null
grep -F "exit_code=0" "$PREFLIGHT_REPORT/result.txt" >/dev/null
grep -F "preflight=passed" "$PREFLIGHT_REPORT/result.txt" >/dev/null

DIRECT_REPORT="$WORK/direct-control-report"
CODEXDOCK_FAKE_LOG="$FAKE_LOG" \
  CODEXDOCK_FAKE_SESSION_DIR="$DIRECT_SESSION_DIR" \
  PATH="$FAKE_BIN:$PATH" \
  CODEXDOCK_HOST=100.64.0.10 \
  CODEXDOCK_USER=manoj \
  CODEXDOCK_CONTROL_URL=https://control.example \
  CODEXDOCK_REPORT_DIR="$DIRECT_REPORT" \
  GOCACHE="$GOCACHE" \
  GOMODCACHE="$GOMODCACHE" \
  "$ROOT/scripts/e2e-remote.sh" >"$WORK/direct-control-e2e.out"
grep -F "remote e2e ok" "$WORK/direct-control-e2e.out" >/dev/null
grep -F "control_url=https://control.example" "$DIRECT_REPORT/context.txt" >/dev/null
grep -F -- "--control-url https://control.example" "$DIRECT_REPORT/init.cmd" >/dev/null
"$ROOT/scripts/validate-e2e-report.sh" --full "$DIRECT_REPORT" >"$WORK/direct-control-validate.out"
grep -F "remote E2E full report ok" "$WORK/direct-control-validate.out" >/dev/null

BIN_MODE_REPORT="$WORK/bin-mode-report"
CODEXDOCK_FAKE_LOG="$FAKE_LOG" \
  CODEXDOCK_FAKE_SESSION_DIR="$BIN_MODE_SESSION_DIR" \
  PATH="$FAKE_BIN:$PATH" \
  CODEXDOCK_BIN="$BIN" \
  CODEXDOCK_HOST=100.64.0.10 \
  CODEXDOCK_USER=manoj \
  CODEXDOCK_REPORT_DIR="$BIN_MODE_REPORT" \
  "$ROOT/scripts/e2e-remote.sh" >"$WORK/bin-mode-e2e.out"
grep -F "remote e2e ok" "$WORK/bin-mode-e2e.out" >/dev/null
grep -F "CODEXDOCK_BIN=$BIN" "$BIN_MODE_REPORT/build.cmd" >/dev/null
grep -F "codexdock $VERSION" "$BIN_MODE_REPORT/build.out" >/dev/null
"$ROOT/scripts/validate-e2e-report.sh" --full "$BIN_MODE_REPORT" >"$WORK/bin-mode-validate.out"
grep -F "remote E2E full report ok" "$WORK/bin-mode-validate.out" >/dev/null

run() {
  CODEXDOCK_FAKE_LOG="$FAKE_LOG" CODEXDOCK_FAKE_SESSION_DIR="$FAKE_SESSION_DIR" PATH="$FAKE_BIN:$PATH" HOME="$HOME_DIR" "$BIN" "$@"
}

run create personal --role controller --control-url https://control.example --provision >"$WORK/create.out"
grep -F "Provisioned network personal" "$WORK/create.out" >/dev/null
grep -F "codexdock invite personal" "$WORK/create.out" >/dev/null

run invite --ttl 12h --reusable >"$WORK/invite.out"
grep -F "codexdock register <machine> personal --control-url https://control.example --join --enrollment-key tskey-local" "$WORK/invite.out" >/dev/null

CODEXDOCK_FAKE_LOG="$FAKE_LOG" \
  CODEXDOCK_FAKE_SESSION_DIR="$FAKE_SESSION_DIR" \
  PATH="$FAKE_BIN:$PATH" \
  HOME="$JOIN_HOME_DIR" \
  "$BIN" register macbook personal --control-url https://control.example --ssh-user manoj --join --enrollment-key tskey-local >"$WORK/join-clean.out"
grep -F "Joined macbook to personal" "$WORK/join-clean.out" >/dev/null
grep -F "Registered macbook in personal" "$WORK/join-clean.out" >/dev/null
if grep -F "tskey-local" "$WORK/join-clean.out" >/dev/null; then
  echo "register --join printed the enrollment key" >&2
  exit 1
fi
grep -F "control_url: https://control.example" "$JOIN_HOME_DIR/.codexdock/config.yaml" >/dev/null
CODEXDOCK_FAKE_LOG="$FAKE_LOG" \
  CODEXDOCK_FAKE_SESSION_DIR="$FAKE_SESSION_DIR" \
  PATH="$FAKE_BIN:$PATH" \
  HOME="$JOIN_HOME_DIR" \
  "$BIN" devices >"$WORK/join-clean-devices.out"
grep -F "macbook	100.64.0.10	manoj	developer	online" "$WORK/join-clean-devices.out" >/dev/null

run register macbook --control-url https://control.example --ssh-user manoj --join --enrollment-key tskey-local >"$WORK/register.out"
grep -F "Joined macbook to personal" "$WORK/register.out" >/dev/null
grep -F "Registered macbook in personal" "$WORK/register.out" >/dev/null

run devices >"$WORK/devices.out"
grep -F "macbook	100.64.0.10	manoj	developer	online" "$WORK/devices.out" >/dev/null

run machines >"$WORK/machines.out"
grep -F "macbook	100.64.0.10	manoj	developer	online" "$WORK/machines.out" >/dev/null

run devices --all >"$WORK/devices-all.out"
grep -F "homepc	100.64.0.2	-	unregistered	online" "$WORK/devices-all.out" >/dev/null
grep -F "codexdock adopt homepc" "$WORK/devices-all.out" >/dev/null

run doctor --repair-plan --target-os linux --role codex-host --workspace '~/code' >"$WORK/codex-host-repair.out"
grep -F "CodexDock repair plan (codex-host)" "$WORK/codex-host-repair.out" >/dev/null
grep -F "sudo apt update && sudo apt install -y openssh-server && (sudo systemctl enable --now ssh || sudo service ssh start)" "$WORK/codex-host-repair.out" >/dev/null
grep -F "sudo apt update && sudo apt install -y tmux" "$WORK/codex-host-repair.out" >/dev/null
grep -F 'mkdir -p "$HOME/code"' "$WORK/codex-host-repair.out" >/dev/null

run adopt homepc --ssh-user manoj >"$WORK/adopt.out"
grep -F "Adopted homepc in personal at 100.64.0.2" "$WORK/adopt.out" >/dev/null
run adopt homepc --ssh-user manoj --workspace '~/src' --force >"$WORK/adopt-force.out"
grep -F "Adopted homepc in personal at 100.64.0.2" "$WORK/adopt-force.out" >/dev/null

run doctor macbook --repair-plan --target-os linux --role codex-host >"$WORK/remote-repair-plan.out"
grep -F "CodexDock remote repair plan for macbook (codex-host)" "$WORK/remote-repair-plan.out" >/dev/null
grep -F "ssh manoj@100.64.0.10 'sudo apt update && sudo apt install -y openssh-server && (sudo systemctl enable --now ssh || sudo service ssh start)'" "$WORK/remote-repair-plan.out" >/dev/null
grep -F "ssh manoj@100.64.0.10 'sudo apt update && sudo apt install -y tmux'" "$WORK/remote-repair-plan.out" >/dev/null

run doctor macbook --repair --yes --target-os linux --role codex-host >"$WORK/remote-repair.out"
grep -F "CodexDock remote repair plan for macbook (codex-host)" "$WORK/remote-repair.out" >/dev/null

run doctor macbook >"$WORK/doctor.out"
grep -F "ok can connect to macbook" "$WORK/doctor.out" >/dev/null
grep -F "ok remote tmux found" "$WORK/doctor.out" >/dev/null
grep -F "ok remote codex found" "$WORK/doctor.out" >/dev/null
grep -F "ok workspace exists" "$WORK/doctor.out" >/dev/null
run doctor --all >"$WORK/doctor-all.out"
grep -F "ok can connect to homepc" "$WORK/doctor-all.out" >/dev/null
grep -F "ok can connect to macbook" "$WORK/doctor-all.out" >/dev/null

run connect homepc
start_log_offset=$(wc -c <"$FAKE_LOG")
run start macbook >"$WORK/start.out"
grep -F "Started Codex session 'codex' on macbook." "$WORK/start.out" >/dev/null
grep -F "codexdock attach macbook" "$WORK/start.out" >/dev/null
tail -c +"$((start_log_offset + 1))" "$FAKE_LOG" >"$WORK/start-log.out"
grep -F "ssh -p 22 manoj@100.64.0.10 true" "$WORK/start-log.out" >/dev/null
grep -F "ssh -p 22 manoj@100.64.0.10 command -v tmux" "$WORK/start-log.out" >/dev/null
grep -F "ssh -p 22 manoj@100.64.0.10 command -v codex" "$WORK/start-log.out" >/dev/null
grep -F 'ssh -p 22 manoj@100.64.0.10 test -d $HOME/code' "$WORK/start-log.out" >/dev/null
grep -F "ssh -p 22 manoj@100.64.0.10 tmux has-session -t codex" "$WORK/start-log.out" >/dev/null
start_preflight_line=$(grep -nF "command -v codex" "$WORK/start-log.out" | sed -n '1s/:.*//p')
start_tmux_line=$(grep -nF "tmux new-session -d" "$WORK/start-log.out" | sed -n '1s/:.*//p')
test "$start_preflight_line" -lt "$start_tmux_line"
run start macbook >"$WORK/start-existing.out"
grep -F "Codex session 'codex' already running on macbook." "$WORK/start-existing.out" >/dev/null
grep -F "codexdock attach macbook" "$WORK/start-existing.out" >/dev/null
attach_log_offset=$(wc -c <"$FAKE_LOG")
run attach macbook
tail -c +"$((attach_log_offset + 1))" "$FAKE_LOG" >"$WORK/attach-log.out"
grep -F "ssh -p 22 manoj@100.64.0.10 tmux has-session -t codex" "$WORK/attach-log.out" >/dev/null
grep -F "ssh -t -p 22 manoj@100.64.0.10 tmux attach -t codex" "$WORK/attach-log.out" >/dev/null
attach_check_line=$(grep -nF "tmux has-session -t codex" "$WORK/attach-log.out" | sed -n '1s/:.*//p')
attach_interactive_line=$(grep -nF "tmux attach -t codex" "$WORK/attach-log.out" | sed -n '1s/:.*//p')
test "$attach_check_line" -lt "$attach_interactive_line"
run sessions macbook >"$WORK/sessions.out"
grep -F "macbook	codex	running" "$WORK/sessions.out" >/dev/null
run sessions >"$WORK/sessions-all.out"
grep -F "macbook	codex	running" "$WORK/sessions-all.out" >/dev/null
send_log_offset=$(wc -c <"$FAKE_LOG")
run send macbook continue with context >"$WORK/send.out"
grep -F "Sent prompt to codex on macbook." "$WORK/send.out" >/dev/null
tail -c +"$((send_log_offset + 1))" "$FAKE_LOG" >"$WORK/send-log.out"
grep -F "ssh -p 22 manoj@100.64.0.10 tmux has-session -t codex" "$WORK/send-log.out" >/dev/null
grep -F "ssh -p 22 manoj@100.64.0.10 tmux send-keys -t codex 'continue with context' Enter" "$WORK/send-log.out" >/dev/null
send_check_line=$(grep -nF "tmux has-session -t codex" "$WORK/send-log.out" | sed -n '1s/:.*//p')
send_keys_line=$(grep -nF "tmux send-keys -t codex" "$WORK/send-log.out" | sed -n '1s/:.*//p')
test "$send_check_line" -lt "$send_keys_line"
logs_log_offset=$(wc -c <"$FAKE_LOG")
run logs macbook --lines 20 >"$WORK/logs.out"
grep -F "codex simulated log" "$WORK/logs.out" >/dev/null
tail -c +"$((logs_log_offset + 1))" "$FAKE_LOG" >"$WORK/logs-log.out"
grep -F "ssh -p 22 manoj@100.64.0.10 tmux has-session -t codex" "$WORK/logs-log.out" >/dev/null
grep -F "ssh -p 22 manoj@100.64.0.10 tmux capture-pane -t codex -p -S -20" "$WORK/logs-log.out" >/dev/null
logs_check_line=$(grep -nF "tmux has-session -t codex" "$WORK/logs-log.out" | sed -n '1s/:.*//p')
logs_capture_line=$(grep -nF "tmux capture-pane -t codex" "$WORK/logs-log.out" | sed -n '1s/:.*//p')
test "$logs_check_line" -lt "$logs_capture_line"
stop_log_offset=$(wc -c <"$FAKE_LOG")
run stop macbook --force >"$WORK/stop.out" 2>"$WORK/stop.err"
grep -F "Stopped Codex session 'codex' on macbook." "$WORK/stop.out" >/dev/null
grep -F "warning: Codex session 'codex' on macbook will be killed." "$WORK/stop.err" >/dev/null
tail -c +"$((stop_log_offset + 1))" "$FAKE_LOG" >"$WORK/stop-log.out"
grep -F "ssh -p 22 manoj@100.64.0.10 tmux has-session -t codex" "$WORK/stop-log.out" >/dev/null
grep -F "ssh -p 22 manoj@100.64.0.10 tmux kill-session -t codex" "$WORK/stop-log.out" >/dev/null
stop_check_line=$(grep -nF "tmux has-session -t codex" "$WORK/stop-log.out" | sed -n '1s/:.*//p')
stop_kill_line=$(grep -nF "tmux kill-session -t codex" "$WORK/stop-log.out" | sed -n '1s/:.*//p')
test "$stop_check_line" -lt "$stop_kill_line"

REMOTE_REPORT="$WORK/remote-report"
MAC_KEY="$WORK/mac.pub"
printf '%s\n' "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICodexDockTestKey macbook" >"$MAC_KEY"
CODEXDOCK_FAKE_LOG="$FAKE_LOG" \
  CODEXDOCK_FAKE_SESSION_DIR="$FAKE_SESSION_DIR" \
  PATH="$FAKE_BIN:$PATH" \
  GOCACHE="$GOCACHE" \
  GOMODCACHE="$GOMODCACHE" \
  CODEXDOCK_HOST=100.64.0.10 \
  CODEXDOCK_USER=manoj \
  CODEXDOCK_PREPARE=1 \
  CODEXDOCK_SSH_AUTHORIZED_KEY_FILE="$MAC_KEY" \
  CODEXDOCK_LOG_LINES=20 \
  CODEXDOCK_TARGET_ARCH=arm64 \
  CODEXDOCK_REPORT_DIR="$REMOTE_REPORT" \
  "$ROOT/scripts/e2e-remote.sh" >"$WORK/remote-e2e.out"
grep -F "remote e2e ok" "$WORK/remote-e2e.out" >/dev/null
test -f "$REMOTE_REPORT/init.out"
test -f "$REMOTE_REPORT/prepare.out"
test -f "$REMOTE_REPORT/doctor.out"
test -f "$REMOTE_REPORT/doctor_all.out"
test -f "$REMOTE_REPORT/start.out"
test -f "$REMOTE_REPORT/sessions.out"
test -f "$REMOTE_REPORT/sessions_all.out"
test -f "$REMOTE_REPORT/send.out"
test -f "$REMOTE_REPORT/logs.out"
test -f "$REMOTE_REPORT/stop.out"
test -f "$REMOTE_REPORT/stop.err"
test -f "$REMOTE_REPORT/sessions_after_stop.out"
test -f "$REMOTE_REPORT/result.txt"
grep -F "ssh_authorized_key_set=no" "$REMOTE_REPORT/context.txt" >/dev/null
grep -F "ssh_authorized_key_file_set=yes" "$REMOTE_REPORT/context.txt" >/dev/null
grep -F "require_scp=0" "$REMOTE_REPORT/context.txt" >/dev/null
grep -F "target_arch=arm64" "$REMOTE_REPORT/context.txt" >/dev/null
grep -F "status=success" "$REMOTE_REPORT/result.txt" >/dev/null
grep -F "exit_code=0" "$REMOTE_REPORT/result.txt" >/dev/null
grep -F "cleanup_attempted=no" "$REMOTE_REPORT/result.txt" >/dev/null
grep -F "ok remote tmux found" "$REMOTE_REPORT/doctor.out" >/dev/null
grep -F "ok can connect to homepc" "$REMOTE_REPORT/doctor_all.out" >/dev/null
grep -F "Started Codex session 'codexdock-e2e' on homepc." "$REMOTE_REPORT/start.out" >/dev/null
grep -F "homepc	codexdock-e2e	running" "$REMOTE_REPORT/sessions_all.out" >/dev/null
grep -F "Sent prompt to codexdock-e2e on homepc." "$REMOTE_REPORT/send.out" >/dev/null
grep -F "codex simulated log" "$REMOTE_REPORT/logs.out" >/dev/null
grep -F "Stopped Codex session 'codexdock-e2e' on homepc." "$REMOTE_REPORT/stop.out" >/dev/null
grep -F "warning: Codex session 'codexdock-e2e' on homepc will be killed." "$REMOTE_REPORT/stop.err" >/dev/null
grep -F "No tmux sessions found on homepc." "$REMOTE_REPORT/sessions_after_stop.out" >/dev/null

FAILURE_REPORT="$WORK/failure-report"
if CODEXDOCK_FAKE_LOG="$FAKE_LOG" \
  CODEXDOCK_FAKE_SESSION_DIR="$FAKE_SESSION_DIR" \
  PATH="$FAKE_BIN:$PATH" \
  GOCACHE="$GOCACHE" \
  GOMODCACHE="$GOMODCACHE" \
  CODEXDOCK_HOST=100.64.0.10 \
  CODEXDOCK_USER=manoj \
  CODEXDOCK_E2E_FAIL_AFTER_START=1 \
  CODEXDOCK_LOG_LINES=20 \
  CODEXDOCK_REPORT_DIR="$FAILURE_REPORT" \
  "$ROOT/scripts/e2e-remote.sh" >"$WORK/remote-e2e-failure.out" 2>"$WORK/remote-e2e-failure.err"; then
  echo "expected remote E2E harness to fail after start when forced" >&2
  exit 1
fi
grep -F "remote e2e forced failure after start" "$WORK/remote-e2e-failure.err" >/dev/null
test -f "$FAILURE_REPORT/cleanup_stop.cmd"
test -f "$FAILURE_REPORT/cleanup_stop.out"
test -f "$FAILURE_REPORT/cleanup_stop.err"
test -f "$FAILURE_REPORT/result.txt"
grep -F "Stopped Codex session 'codexdock-e2e' on homepc." "$FAILURE_REPORT/cleanup_stop.out" >/dev/null
grep -F "warning: Codex session 'codexdock-e2e' on homepc will be killed." "$FAILURE_REPORT/cleanup_stop.err" >/dev/null
grep -F "status=failure" "$FAILURE_REPORT/result.txt" >/dev/null
grep -F "exit_code=1" "$FAILURE_REPORT/result.txt" >/dev/null
grep -F "cleanup_attempted=yes" "$FAILURE_REPORT/result.txt" >/dev/null
grep -F "cleanup_exit_code=0" "$FAILURE_REPORT/result.txt" >/dev/null
grep -F "session_stopped=yes" "$FAILURE_REPORT/result.txt" >/dev/null

FAILURE_CLEANUP_REPORT="$WORK/failure-cleanup-report"
: >"$FAKE_SESSION_DIR/fail-kill"
if CODEXDOCK_FAKE_LOG="$FAKE_LOG" \
  CODEXDOCK_FAKE_SESSION_DIR="$FAKE_SESSION_DIR" \
  PATH="$FAKE_BIN:$PATH" \
  GOCACHE="$GOCACHE" \
  GOMODCACHE="$GOMODCACHE" \
  CODEXDOCK_HOST=100.64.0.10 \
  CODEXDOCK_USER=manoj \
  CODEXDOCK_E2E_FAIL_AFTER_START=1 \
  CODEXDOCK_LOG_LINES=20 \
  CODEXDOCK_REPORT_DIR="$FAILURE_CLEANUP_REPORT" \
  "$ROOT/scripts/e2e-remote.sh" >"$WORK/remote-e2e-cleanup-failure.out" 2>"$WORK/remote-e2e-cleanup-failure.err"; then
  echo "expected remote E2E harness to fail after start when forced" >&2
  exit 1
fi
rm -f "$FAKE_SESSION_DIR/fail-kill"
grep -F "remote e2e forced failure after start" "$WORK/remote-e2e-cleanup-failure.err" >/dev/null
test -f "$FAILURE_CLEANUP_REPORT/cleanup_stop.cmd"
test -f "$FAILURE_CLEANUP_REPORT/cleanup_stop.out"
test -f "$FAILURE_CLEANUP_REPORT/cleanup_stop.err"
test -f "$FAILURE_CLEANUP_REPORT/result.txt"
grep -F "exit status 1" "$FAILURE_CLEANUP_REPORT/cleanup_stop.err" >/dev/null
grep -F "status=failure" "$FAILURE_CLEANUP_REPORT/result.txt" >/dev/null
grep -F "exit_code=1" "$FAILURE_CLEANUP_REPORT/result.txt" >/dev/null
grep -F "cleanup_attempted=yes" "$FAILURE_CLEANUP_REPORT/result.txt" >/dev/null
grep -F "cleanup_exit_code=1" "$FAILURE_CLEANUP_REPORT/result.txt" >/dev/null
grep -F "session_stopped=no" "$FAILURE_CLEANUP_REPORT/result.txt" >/dev/null

grep -F "headscale users list --name personal --output=json" "$FAKE_LOG" >/dev/null
grep -F "headscale users create personal" "$FAKE_LOG" >/dev/null
grep -F "headscale preauthkeys create --user 7 --expiration 12h --reusable --output=json" "$FAKE_LOG" >/dev/null
grep -F "tailscale up --login-server=https://control.example --auth-key=tskey-local --hostname=macbook" "$FAKE_LOG" >/dev/null
grep -F "ssh -p 22 manoj@100.64.0.10 sudo apt update && sudo apt install -y openssh-server && (sudo systemctl enable --now ssh || sudo service ssh start)" "$FAKE_LOG" >/dev/null
grep -F "authorized_keys" "$FAKE_LOG" >/dev/null
grep -F "ssh -p 22 manoj@100.64.0.10 sudo apt update && sudo apt install -y tmux" "$FAKE_LOG" >/dev/null
grep -F 'ssh -p 22 manoj@100.64.0.10 mkdir -p "$HOME/code"' "$FAKE_LOG" >/dev/null
grep -F "ssh -p 22 manoj@100.64.0.10 tmux ls" "$FAKE_LOG" >/dev/null

printf 'local simulated e2e ok\n'
