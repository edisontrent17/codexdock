#!/usr/bin/env sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

usage() {
  cat <<EOF
Usage: CODEXDOCK_HOST=<host> CODEXDOCK_USER=<user> $0
       $0 --print-plan
       $0 --preflight
       $0 --write-runbook

Environment:
  CODEXDOCK_HOST       SSH host, private IP, or DNS name for the target machine
  CODEXDOCK_USER       SSH user for the target machine
  CODEXDOCK_ADOPT      Set to 1 to adopt CODEXDOCK_MACHINE from private-network status
  CODEXDOCK_CONTROL_URL Optional control URL stored by direct init or adopt create
  CODEXDOCK_PREPARE    Set to 1 to run remote codex-host repair before validation
  CODEXDOCK_SSH_PORT   SSH port (default: 22)
  CODEXDOCK_NETWORK    CodexDock network name (default: personal)
  CODEXDOCK_MACHINE    CodexDock machine alias (default: homepc)
  CODEXDOCK_WORKSPACE  Remote workspace path (default: ~/code)
  CODEXDOCK_SESSION    Remote tmux session name (default: codexdock-e2e)
  CODEXDOCK_AGENT      Agent command to run inside tmux (default: codex)
  CODEXDOCK_PROMPT     Prompt sent during validation (default: codexdock smoke ping)
  CODEXDOCK_LOG_LINES  Log lines to capture (default: 40)
  CODEXDOCK_SSH_AUTHORIZED_KEY Optional public key to add during CODEXDOCK_PREPARE=1
  CODEXDOCK_SSH_AUTHORIZED_KEY_FILE Optional public key file to add during CODEXDOCK_PREPARE=1
  CODEXDOCK_BIN       Optional local codexdock binary to validate instead of building from source
  CODEXDOCK_REQUIRE_SCP Set to 1 when preflight must verify scp for runbook staging
  CODEXDOCK_TARGET_ARCH Linux GOARCH for runbook WSL staging (default: amd64)
  CODEXDOCK_REPORT_DIR Directory for command outputs (default: .dev-logs/e2e-remote/<timestamp>)
EOF
}

trim_value() {
  printf '%s' "$1" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
}

if [ "${CODEXDOCK_NETWORK+x}" = x ]; then NETWORK_PROVIDED=1; else NETWORK_PROVIDED=0; fi
if [ "${CODEXDOCK_MACHINE+x}" = x ]; then MACHINE_PROVIDED=1; else MACHINE_PROVIDED=0; fi
if [ "${CODEXDOCK_HOST+x}" = x ]; then HOST_PROVIDED=1; else HOST_PROVIDED=0; fi
if [ "${CODEXDOCK_USER+x}" = x ]; then SSH_USER_PROVIDED=1; else SSH_USER_PROVIDED=0; fi
if [ "${CODEXDOCK_CONTROL_URL+x}" = x ]; then CONTROL_URL_PROVIDED=1; else CONTROL_URL_PROVIDED=0; fi
if [ "${CODEXDOCK_WORKSPACE+x}" = x ]; then WORKSPACE_PROVIDED=1; else WORKSPACE_PROVIDED=0; fi
if [ "${CODEXDOCK_SSH_AUTHORIZED_KEY+x}" = x ]; then SSH_AUTHORIZED_KEY_PROVIDED=1; else SSH_AUTHORIZED_KEY_PROVIDED=0; fi
if [ "${CODEXDOCK_SSH_AUTHORIZED_KEY_FILE+x}" = x ]; then SSH_AUTHORIZED_KEY_FILE_PROVIDED=1; else SSH_AUTHORIZED_KEY_FILE_PROVIDED=0; fi
if [ "${CODEXDOCK_BIN+x}" = x ]; then CODEXDOCK_BIN_PROVIDED=1; else CODEXDOCK_BIN_PROVIDED=0; fi

NETWORK=$(trim_value "${CODEXDOCK_NETWORK:-personal}")
MACHINE=$(trim_value "${CODEXDOCK_MACHINE:-homepc}")
HOST=$(trim_value "${CODEXDOCK_HOST:-}")
SSH_USER=$(trim_value "${CODEXDOCK_USER:-}")
ADOPT=$(trim_value "${CODEXDOCK_ADOPT:-0}")
PREPARE=$(trim_value "${CODEXDOCK_PREPARE:-0}")
CONTROL_URL=$(trim_value "${CODEXDOCK_CONTROL_URL:-}")
SSH_PORT=$(trim_value "${CODEXDOCK_SSH_PORT:-22}")
WORKSPACE=$(trim_value "${CODEXDOCK_WORKSPACE:-}")
if [ "$WORKSPACE_PROVIDED" = "0" ] && [ -z "$WORKSPACE" ]; then
  WORKSPACE='~/code'
fi
SESSION=$(trim_value "${CODEXDOCK_SESSION:-codexdock-e2e}")
AGENT=$(trim_value "${CODEXDOCK_AGENT:-codex}")
PROMPT=$(trim_value "${CODEXDOCK_PROMPT:-codexdock smoke ping}")
LOG_LINES=$(trim_value "${CODEXDOCK_LOG_LINES:-40}")
SSH_AUTHORIZED_KEY=$(trim_value "${CODEXDOCK_SSH_AUTHORIZED_KEY:-}")
SSH_AUTHORIZED_KEY_FILE=$(trim_value "${CODEXDOCK_SSH_AUTHORIZED_KEY_FILE:-}")
CODEXDOCK_BIN=$(trim_value "${CODEXDOCK_BIN:-}")
REQUIRE_SCP=$(trim_value "${CODEXDOCK_REQUIRE_SCP:-0}")
TARGET_ARCH=$(trim_value "${CODEXDOCK_TARGET_ARCH:-amd64}")

print_plan() {
  host_label=${HOST:-<CODEXDOCK_HOST>}
  user_label=${SSH_USER:-<CODEXDOCK_USER>}
  if [ "$ADOPT" = "1" ]; then
    control_arg=""
    if [ -n "$CONTROL_URL" ]; then
      control_arg=" --control-url $CONTROL_URL"
    fi
    cat <<EOF
Remote E2E plan
  required: CODEXDOCK_USER and a visible private-network peer named $MACHINE
  mode: adopt
  network: $NETWORK
  machine: $MACHINE
  workspace: $WORKSPACE
  session: $SESSION
  agent: $AGENT
  report directory: CODEXDOCK_REPORT_DIR or .dev-logs/e2e-remote/<timestamp>
  target prep on WSL/Linux host:
    codexdock doctor --repair-plan --target-os linux --role codex-host --workspace "$WORKSPACE"
    optional SSH key: CODEXDOCK_SSH_AUTHORIZED_KEY or CODEXDOCK_SSH_AUTHORIZED_KEY_FILE adds --ssh-authorized-key to CODEXDOCK_PREPARE=1
  commands:
    codexdock create $NETWORK$control_arg
    codexdock adopt $MACHINE --ssh-user $user_label --ssh-port $SSH_PORT --workspace "$WORKSPACE" --session $SESSION --agent "$AGENT"
    optional prep:
      CODEXDOCK_PREPARE=1 runs codexdock doctor $MACHINE --repair --yes --target-os linux --role codex-host
    codexdock doctor $MACHINE
    codexdock doctor --all
    codexdock start $MACHINE
    codexdock sessions $MACHINE
    codexdock sessions
    codexdock send $MACHINE "$PROMPT"
    codexdock logs $MACHINE --lines $LOG_LINES
    codexdock stop $MACHINE --force
    codexdock sessions $MACHINE
EOF
    return
  fi
  control_arg=""
  if [ -n "$CONTROL_URL" ]; then
    control_arg=" --control-url $CONTROL_URL"
  fi
  cat <<EOF
Remote E2E plan
  required: CODEXDOCK_HOST, CODEXDOCK_USER
  network: $NETWORK
  machine: $MACHINE
  target: $user_label@$host_label:$SSH_PORT
  workspace: $WORKSPACE
  session: $SESSION
  agent: $AGENT
  report directory: CODEXDOCK_REPORT_DIR or .dev-logs/e2e-remote/<timestamp>
  target prep on WSL/Linux host:
    codexdock doctor --repair-plan --target-os linux --role codex-host --workspace "$WORKSPACE"
    optional SSH key: CODEXDOCK_SSH_AUTHORIZED_KEY or CODEXDOCK_SSH_AUTHORIZED_KEY_FILE adds --ssh-authorized-key to CODEXDOCK_PREPARE=1
  commands:
    codexdock init --network $NETWORK --machine $MACHINE --host $host_label --ssh-user $user_label --ssh-port $SSH_PORT$control_arg --workspace "$WORKSPACE" --session $SESSION --agent "$AGENT"
    optional prep:
      CODEXDOCK_PREPARE=1 runs codexdock doctor $MACHINE --repair --yes --target-os linux --role codex-host
    codexdock doctor $MACHINE
    codexdock doctor --all
    codexdock start $MACHINE
    codexdock sessions $MACHINE
    codexdock sessions
    codexdock send $MACHINE "$PROMPT"
    codexdock logs $MACHINE --lines $LOG_LINES
    codexdock stop $MACHINE --force
    codexdock sessions $MACHINE
EOF
}

ensure_report_dir() {
  if [ -n "${CODEXDOCK_REPORT_DIR:-}" ]; then
    REPORT_DIR=$CODEXDOCK_REPORT_DIR
  else
    REPORT_DIR="$ROOT/.dev-logs/e2e-remote/$(date -u +%Y%m%dT%H%M%SZ)"
  fi
  mkdir -p "$REPORT_DIR"
}

append_name() {
  if [ -z "$1" ]; then
    printf '%s' "$2"
  else
    printf '%s %s' "$1" "$2"
  fi
}

append_invalid() {
  if [ "$1" = "none" ]; then
    printf '%s' "$2"
  else
    printf '%s; %s' "$1" "$2"
  fi
}

command_status() {
  if command -v "$1" >/dev/null 2>&1; then
    printf yes
  else
    printf no
  fi
}

require_target_inputs() {
  target_invalids=none
  target_message=$(target_host_error)
  if [ -n "$target_message" ]; then
    target_invalids=$(append_invalid "$target_invalids" "$target_message")
  fi
  target_message=$(target_user_error)
  if [ -n "$target_message" ]; then
    target_invalids=$(append_invalid "$target_invalids" "$target_message")
  fi
  if [ "$target_invalids" != "none" ]; then
    echo "$target_invalids" >&2
    exit 2
  fi
}

blank_value_error() {
  name=$1
  value=$2
  if [ -z "$value" ]; then
    return 0
  fi
  case "$value" in
    *[![:space:]]*) ;;
    *) printf '%s cannot be blank' "$name" ;;
  esac
}

required_value_error() {
  name=$1
  value=$2
  case "$value" in
    *[![:space:]]*) ;;
    *) printf '%s cannot be blank' "$name" ;;
  esac
}

network_error() {
  required_value_error CODEXDOCK_NETWORK "$NETWORK"
}

machine_error() {
  required_value_error CODEXDOCK_MACHINE "$MACHINE"
}

target_host_error() {
  if [ -z "$HOST" ]; then
    if [ "$ADOPT" != "1" ]; then
      if [ "$HOST_PROVIDED" = "1" ]; then
        printf 'CODEXDOCK_HOST cannot be blank'
      else
        printf 'CODEXDOCK_HOST is required'
      fi
    fi
    return 0
  fi
  required_value_error CODEXDOCK_HOST "$HOST"
}

target_user_error() {
  if [ -z "$SSH_USER" ]; then
    if [ "$SSH_USER_PROVIDED" = "1" ]; then
      printf 'CODEXDOCK_USER cannot be blank'
    else
      printf 'CODEXDOCK_USER is required'
    fi
    return 0
  fi
  required_value_error CODEXDOCK_USER "$SSH_USER"
}

require_supported_target_arch() {
  case "$TARGET_ARCH" in
    amd64|arm64) ;;
    *)
      echo "unsupported CODEXDOCK_TARGET_ARCH: $TARGET_ARCH (supported: amd64, arm64)" >&2
      exit 2
      ;;
  esac
}

target_arch_error() {
  case "$TARGET_ARCH" in
    amd64|arm64) ;;
    *)
      printf 'unsupported CODEXDOCK_TARGET_ARCH: %s (supported: amd64, arm64)' "$TARGET_ARCH"
      ;;
  esac
}

positive_integer_error() {
  name=$1
  value=$2
  case "$value" in
    ''|*[!0-9]*)
      printf '%s must be a positive integer' "$name"
      return 0
      ;;
  esac
  if [ "$value" -eq 0 ]; then
    printf '%s must be a positive integer' "$name"
  fi
}

ssh_port_error() {
  positive_integer_error CODEXDOCK_SSH_PORT "$SSH_PORT"
}

log_lines_error() {
  positive_integer_error CODEXDOCK_LOG_LINES "$LOG_LINES"
}

flag_error() {
  name=$1
  value=$2
  case "$value" in
    0|1) ;;
    *)
      printf '%s must be 0 or 1' "$name"
      ;;
  esac
}

adopt_flag_error() {
  flag_error CODEXDOCK_ADOPT "$ADOPT"
}

prepare_flag_error() {
  flag_error CODEXDOCK_PREPARE "$PREPARE"
}

require_scp_flag_error() {
  flag_error CODEXDOCK_REQUIRE_SCP "$REQUIRE_SCP"
}

control_url_error() {
  if [ -z "$CONTROL_URL" ]; then
    if [ "$CONTROL_URL_PROVIDED" = "1" ]; then
      printf 'CODEXDOCK_CONTROL_URL cannot be blank'
    fi
    return 0
  fi
  required_value_error CODEXDOCK_CONTROL_URL "$CONTROL_URL"
}

workspace_error() {
  required_value_error CODEXDOCK_WORKSPACE "$WORKSPACE"
}

session_error() {
  message=$(required_value_error CODEXDOCK_SESSION "$SESSION")
  if [ -n "$message" ]; then
    printf '%s' "$message"
    return 0
  fi
  case "$SESSION" in
    ''|*[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-]*)
      printf 'CODEXDOCK_SESSION must contain only letters, numbers, underscores, or hyphens'
      ;;
  esac
}

agent_error() {
  required_value_error CODEXDOCK_AGENT "$AGENT"
}

prompt_error() {
  required_value_error CODEXDOCK_PROMPT "$PROMPT"
}

require_valid_profile() {
  profile_invalids=none
  profile_message=$(workspace_error)
  if [ -n "$profile_message" ]; then
    profile_invalids=$(append_invalid "$profile_invalids" "$profile_message")
  fi
  profile_message=$(session_error)
  if [ -n "$profile_message" ]; then
    profile_invalids=$(append_invalid "$profile_invalids" "$profile_message")
  fi
  profile_message=$(agent_error)
  if [ -n "$profile_message" ]; then
    profile_invalids=$(append_invalid "$profile_invalids" "$profile_message")
  fi
  profile_message=$(prompt_error)
  if [ -n "$profile_message" ]; then
    profile_invalids=$(append_invalid "$profile_invalids" "$profile_message")
  fi
  if [ "$profile_invalids" != "none" ]; then
    echo "$profile_invalids" >&2
    exit 2
  fi
}

require_valid_identity() {
  identity_invalids=none
  identity_message=$(network_error)
  if [ -n "$identity_message" ]; then
    identity_invalids=$(append_invalid "$identity_invalids" "$identity_message")
  fi
  identity_message=$(machine_error)
  if [ -n "$identity_message" ]; then
    identity_invalids=$(append_invalid "$identity_invalids" "$identity_message")
  fi
  if [ "$identity_invalids" != "none" ]; then
    echo "$identity_invalids" >&2
    exit 2
  fi
}

ssh_authorized_key_error() {
  if [ "$SSH_AUTHORIZED_KEY_PROVIDED" = "1" ]; then
    required_value_error CODEXDOCK_SSH_AUTHORIZED_KEY "$SSH_AUTHORIZED_KEY"
  fi
}

ssh_authorized_key_file_path_error() {
  if [ "$SSH_AUTHORIZED_KEY_FILE_PROVIDED" = "1" ]; then
    required_value_error CODEXDOCK_SSH_AUTHORIZED_KEY_FILE "$SSH_AUTHORIZED_KEY_FILE"
  fi
}

ssh_authorized_key_file_content_is_blank() {
  key_line=$(sed -n '1p' "$SSH_AUTHORIZED_KEY_FILE")
  case "$key_line" in
    *[![:space:]]*) return 1 ;;
    *) return 0 ;;
  esac
}

require_valid_ssh_authorized_key_sources() {
  key_invalids=none
  key_message=$(ssh_authorized_key_error)
  if [ -n "$key_message" ]; then
    key_invalids=$(append_invalid "$key_invalids" "$key_message")
  fi
  file_message=$(ssh_authorized_key_file_path_error)
  if [ -n "$file_message" ]; then
    key_invalids=$(append_invalid "$key_invalids" "$file_message")
  fi
  if [ -n "$SSH_AUTHORIZED_KEY" ] && [ -n "$SSH_AUTHORIZED_KEY_FILE" ]; then
    key_invalids=$(append_invalid "$key_invalids" "set either CODEXDOCK_SSH_AUTHORIZED_KEY or CODEXDOCK_SSH_AUTHORIZED_KEY_FILE, not both")
  elif [ -n "$SSH_AUTHORIZED_KEY_FILE" ] && [ -z "$file_message" ]; then
    if [ ! -f "$SSH_AUTHORIZED_KEY_FILE" ]; then
      key_invalids=$(append_invalid "$key_invalids" "CODEXDOCK_SSH_AUTHORIZED_KEY_FILE does not exist: $SSH_AUTHORIZED_KEY_FILE")
    elif ssh_authorized_key_file_content_is_blank; then
      key_invalids=$(append_invalid "$key_invalids" "CODEXDOCK_SSH_AUTHORIZED_KEY_FILE is empty: $SSH_AUTHORIZED_KEY_FILE")
    fi
  fi
  if [ "$key_invalids" != "none" ]; then
    echo "$key_invalids" >&2
    exit 2
  fi
}

require_valid_flags() {
  flag_invalids=none
  flag_message=$(adopt_flag_error)
  if [ -n "$flag_message" ]; then
    flag_invalids=$(append_invalid "$flag_invalids" "$flag_message")
  fi
  flag_message=$(prepare_flag_error)
  if [ -n "$flag_message" ]; then
    flag_invalids=$(append_invalid "$flag_invalids" "$flag_message")
  fi
  flag_message=$(require_scp_flag_error)
  if [ -n "$flag_message" ]; then
    flag_invalids=$(append_invalid "$flag_invalids" "$flag_message")
  fi
  if [ "$flag_invalids" != "none" ]; then
    echo "$flag_invalids" >&2
    exit 2
  fi
}

require_valid_ssh_port() {
  message=$(ssh_port_error)
  if [ -n "$message" ]; then
    echo "$message: $SSH_PORT" >&2
    exit 2
  fi
}

require_valid_log_lines() {
  message=$(log_lines_error)
  if [ -n "$message" ]; then
    echo "$message: $LOG_LINES" >&2
    exit 2
  fi
}

require_valid_control_url() {
  message=$(control_url_error)
  if [ -n "$message" ]; then
    echo "$message" >&2
    exit 2
  fi
}

codexdock_bin_error() {
  if [ "$CODEXDOCK_BIN_PROVIDED" != "1" ]; then
    return 0
  fi
  if [ -z "$CODEXDOCK_BIN" ]; then
    printf 'CODEXDOCK_BIN cannot be blank'
    return 0
  fi
  if [ ! -f "$CODEXDOCK_BIN" ] || [ ! -x "$CODEXDOCK_BIN" ]; then
    printf 'CODEXDOCK_BIN is not executable: %s' "$CODEXDOCK_BIN"
  fi
}

require_valid_codexdock_bin() {
  message=$(codexdock_bin_error)
  if [ -n "$message" ]; then
    echo "$message" >&2
    exit 2
  fi
}

quote_sh() {
  printf "'"
  printf '%s' "$1" | sed "s/'/'\\\\''/g"
  printf "'"
}

write_run_env() {
  target=$1
  mode=$2
  require_scp=${3:-0}
  {
    printf '#!/usr/bin/env sh\n'
    printf 'set -eu\n'
    printf 'cd %s\n' "$(quote_sh "$ROOT")"
    printf 'env \\\n'
    printf '  GOCACHE=%s \\\n' "$(quote_sh "/tmp/codexdock-gocache")"
    printf '  GOMODCACHE=%s \\\n' "$(quote_sh "/tmp/codexdock-gomodcache")"
    if [ -n "$CODEXDOCK_BIN" ]; then
      printf '  CODEXDOCK_BIN=%s \\\n' "$(quote_sh "$CODEXDOCK_BIN")"
    fi
    printf '  CODEXDOCK_NETWORK=%s \\\n' "$(quote_sh "$NETWORK")"
    printf '  CODEXDOCK_MACHINE=%s \\\n' "$(quote_sh "$MACHINE")"
    printf '  CODEXDOCK_HOST=%s \\\n' "$(quote_sh "$HOST")"
    printf '  CODEXDOCK_USER=%s \\\n' "$(quote_sh "$SSH_USER")"
    printf '  CODEXDOCK_ADOPT=%s \\\n' "$(quote_sh "$ADOPT")"
    printf '  CODEXDOCK_CONTROL_URL=%s \\\n' "$(quote_sh "$CONTROL_URL")"
    printf '  CODEXDOCK_PREPARE=%s \\\n' "$(quote_sh "$PREPARE")"
    printf '  CODEXDOCK_SSH_PORT=%s \\\n' "$(quote_sh "$SSH_PORT")"
    printf '  CODEXDOCK_WORKSPACE=%s \\\n' "$(quote_sh "$WORKSPACE")"
    printf '  CODEXDOCK_SESSION=%s \\\n' "$(quote_sh "$SESSION")"
    printf '  CODEXDOCK_AGENT=%s \\\n' "$(quote_sh "$AGENT")"
    printf '  CODEXDOCK_PROMPT=%s \\\n' "$(quote_sh "$PROMPT")"
    printf '  CODEXDOCK_LOG_LINES=%s \\\n' "$(quote_sh "$LOG_LINES")"
    printf '  CODEXDOCK_SSH_AUTHORIZED_KEY=%s \\\n' "$(quote_sh "$SSH_AUTHORIZED_KEY")"
    printf '  CODEXDOCK_SSH_AUTHORIZED_KEY_FILE=%s \\\n' "$(quote_sh "$SSH_AUTHORIZED_KEY_FILE")"
    printf '  CODEXDOCK_REQUIRE_SCP=%s \\\n' "$(quote_sh "$require_scp")"
    printf '  CODEXDOCK_TARGET_ARCH=%s \\\n' "$(quote_sh "$TARGET_ARCH")"
    printf '  CODEXDOCK_REPORT_DIR=%s \\\n' "$(quote_sh "$REPORT_DIR")"
    if [ "$mode" = "preflight" ]; then
      printf '  ./scripts/e2e-remote.sh --preflight\n'
    else
      printf '  ./scripts/e2e-remote.sh\n'
    fi
  } >"$target"
  chmod +x "$target"
}

runbook_ssh_authorized_key_arg() {
  if [ -n "$SSH_AUTHORIZED_KEY" ] && [ -n "$SSH_AUTHORIZED_KEY_FILE" ]; then
    echo "set either CODEXDOCK_SSH_AUTHORIZED_KEY or CODEXDOCK_SSH_AUTHORIZED_KEY_FILE, not both" >&2
    exit 2
  fi
  key=$SSH_AUTHORIZED_KEY
  if [ -n "$SSH_AUTHORIZED_KEY_FILE" ]; then
    if [ ! -f "$SSH_AUTHORIZED_KEY_FILE" ]; then
      echo "CODEXDOCK_SSH_AUTHORIZED_KEY_FILE does not exist: $SSH_AUTHORIZED_KEY_FILE" >&2
      exit 2
    fi
    key=$(trim_value "$(sed -n '1p' "$SSH_AUTHORIZED_KEY_FILE")")
    if [ -z "$key" ]; then
      echo "CODEXDOCK_SSH_AUTHORIZED_KEY_FILE is empty: $SSH_AUTHORIZED_KEY_FILE" >&2
      exit 2
    fi
  fi
  if [ -n "$key" ]; then
    printf ' --ssh-authorized-key %s' "$(quote_sh "$key")"
  fi
}

write_runbook() {
  require_valid_flags
  require_valid_identity
  require_target_inputs
  require_valid_ssh_port
  require_valid_log_lines
  require_valid_control_url
  require_valid_profile
  require_valid_codexdock_bin
  require_supported_target_arch
  require_valid_ssh_authorized_key_sources
  ssh_key_arg=$(runbook_ssh_authorized_key_arg)
  ensure_report_dir
  write_preflight_context

  wsl_prepare="$REPORT_DIR/wsl-prepare.sh"
  wsl_install="$REPORT_DIR/wsl-install-codexdock.sh"
  wsl_preflight="$REPORT_DIR/wsl-preflight.sh"
  wsl_prepare_plan="$REPORT_DIR/wsl-prepare-plan.sh"
  mac_stage="$REPORT_DIR/mac-stage-wsl-codexdock.sh"
  mac_preflight="$REPORT_DIR/mac-preflight.sh"
  mac_run="$REPORT_DIR/mac-run.sh"
  finalize="$REPORT_DIR/finalize-trent.sh"
  runbook="$REPORT_DIR/runbook.txt"
  linux_binary="$REPORT_DIR/codexdock-linux-$TARGET_ARCH"
  stage_host=$HOST
  if [ -z "$stage_host" ]; then
    stage_host=$MACHINE
  fi
  stage_target="$SSH_USER@$stage_host"

  write_run_env "$mac_preflight" preflight 1
  write_run_env "$mac_run" run 0

  {
    printf '#!/usr/bin/env sh\n'
    printf 'set -eu\n'
    printf 'cd %s\n' "$(quote_sh "$ROOT")"
    printf 'mkdir -p "$HOME/.local/bin"\n'
    printf 'env \\\n'
    printf '  GOCACHE=%s \\\n' "$(quote_sh "/tmp/codexdock-gocache")"
    printf '  GOMODCACHE=%s \\\n' "$(quote_sh "/tmp/codexdock-gomodcache")"
    printf '  OUT="$HOME/.local/bin/codexdock" \\\n'
    printf '  ./scripts/build.sh\n'
    printf 'chmod 755 "$HOME/.local/bin/codexdock"\n'
    printf '"$HOME/.local/bin/codexdock" version\n'
  } >"$wsl_install"
  chmod +x "$wsl_install"

  {
    printf '#!/usr/bin/env sh\n'
    printf 'set -eu\n'
    printf 'cd %s\n' "$(quote_sh "$ROOT")"
    printf 'REPORT=%s\n' "$(quote_sh "$REPORT_DIR/wsl_preflight.txt")"
    printf 'WORKSPACE=%s\n' "$(quote_sh "$WORKSPACE")"
    printf 'ADOPT=%s\n' "$(quote_sh "$ADOPT")"
    printf 'INSTALL=%s\n' "$(quote_sh "$wsl_install")"
    printf 'PREPARE_PLAN=%s\n' "$(quote_sh "$wsl_prepare_plan")"
    printf 'PREPARE=%s\n' "$(quote_sh "$wsl_prepare")"
    printf 'MAC_STAGE=%s\n' "$(quote_sh "$mac_stage")"
    printf 'MAC_PREFLIGHT=%s\n' "$(quote_sh "$mac_preflight")"
    printf 'command_status() {\n'
    printf '  if command -v "$1" >/dev/null 2>&1; then printf yes; else printf no; fi\n'
    printf '}\n'
    printf 'codexdock_bin_status() {\n'
    printf '  bin=${CODEXDOCK_BIN:-"$HOME/.local/bin/codexdock"}\n'
    printf '  if [ -x "$bin" ]; then printf executable; elif command -v codexdock >/dev/null 2>&1; then printf path; else printf missing; fi\n'
    printf '}\n'
    printf 'workspace_real_path() {\n'
    printf '  case "$WORKSPACE" in\n'
    printf '    "~") printf "%%s" "$HOME" ;;\n'
    printf '    "~/"*) printf "%%s/%%s" "$HOME" "${WORKSPACE#\\~/}" ;;\n'
    printf '    *) printf "%%s" "$WORKSPACE" ;;\n'
    printf '  esac\n'
    printf '}\n'
    printf 'workspace_status() {\n'
    printf '  path=$(workspace_real_path)\n'
    printf '  if [ -d "$path" ]; then printf yes; else printf no; fi\n'
    printf '}\n'
    printf 'ssh_listener_status() {\n'
    printf '  if ! command -v ss >/dev/null 2>&1; then printf unknown; return; fi\n'
    printf '  if ss -ltn 2>/dev/null | awk '"'"'NR > 1 {print $4}'"'"' | grep -Eq '"'"'(^|:)22$'"'"'; then printf yes; else printf no; fi\n'
    printf '}\n'
    printf 'private_network_client=$(command_status tailscale)\n'
    printf 'ssh_command=$(command_status ssh)\n'
    printf 'ssh_listener=$(ssh_listener_status)\n'
    printf 'tmux_command=$(command_status tmux)\n'
    printf 'codex_command=$(command_status codex)\n'
    printf 'workspace_exists=$(workspace_status)\n'
    printf 'codexdock_bin=$(codexdock_bin_status)\n'
    printf 'missing=none\n'
    printf 'append_missing() { if [ "$missing" = none ]; then missing=$1; else missing="$missing $1"; fi; }\n'
    printf 'if [ "$ADOPT" = "1" ] && [ "$private_network_client" != yes ]; then append_missing tailscale; fi\n'
    printf 'if [ "$ssh_command" != yes ]; then append_missing ssh; fi\n'
    printf 'if [ "$ssh_listener" != yes ]; then append_missing ssh_listener; fi\n'
    printf 'if [ "$tmux_command" != yes ]; then append_missing tmux; fi\n'
    printf 'if [ "$codex_command" != yes ]; then append_missing codex; fi\n'
    printf 'if [ "$workspace_exists" != yes ]; then append_missing workspace; fi\n'
    printf 'if [ "$codexdock_bin" = missing ]; then append_missing codexdock; fi\n'
    printf 'status=success\n'
    printf 'if [ "$missing" != none ]; then status=failure; fi\n'
    printf 'next_action() {\n'
    printf '  if [ "$status" = success ]; then\n'
    printf '    printf "run %%s from the Mac, then %%s" "$MAC_STAGE" "$MAC_PREFLIGHT"\n'
    printf '    return\n'
    printf '  fi\n'
    printf '  case " $missing " in\n'
    printf '    *" codexdock "*) printf "run %%s, then rerun %%s" "$INSTALL" "$0"; return ;;\n'
    printf '  esac\n'
    printf '  case " $missing " in\n'
    printf '    *" codex "*) printf "install and authenticate Codex CLI for this WSL user, run %%s to inspect remaining steps, run %%s if needed, then rerun %%s" "$PREPARE_PLAN" "$PREPARE" "$0"; return ;;\n'
    printf '  esac\n'
    printf '  printf "run %%s to inspect, run %%s, then rerun %%s" "$PREPARE_PLAN" "$PREPARE" "$0"\n'
    printf '}\n'
    printf 'next_action=$(next_action)\n'
    printf 'cat >"$REPORT" <<EOF\n'
    printf 'status=$status\n'
    printf 'missing=$missing\n'
    printf 'next=$next_action\n'
    printf 'adopt=$ADOPT\n'
    printf 'private_network_client=$private_network_client\n'
    printf 'ssh_command=$ssh_command\n'
    printf 'ssh_listener=$ssh_listener\n'
    printf 'tmux=$tmux_command\n'
    printf 'codex=$codex_command\n'
    printf 'workspace=$WORKSPACE\n'
    printf 'workspace_exists=$workspace_exists\n'
    printf 'codexdock_bin=$codexdock_bin\n'
    printf 'EOF\n'
    printf 'if [ "$status" = success ]; then\n'
    printf '  printf "wsl preflight ok\\n"\n'
    printf 'else\n'
    printf '  printf "wsl preflight failed\\n"\n'
    printf 'fi\n'
    printf 'printf "report: %%s\\n" "$REPORT"\n'
    printf 'printf "next: %%s\\n" "$next_action"\n'
    printf 'if [ "$status" = success ]; then exit 0; fi\n'
    printf 'exit 2\n'
  } >"$wsl_preflight"
  chmod +x "$wsl_preflight"

  {
    printf '#!/usr/bin/env sh\n'
    printf 'set -eu\n'
    printf 'cd %s\n' "$(quote_sh "$ROOT")"
    printf 'env \\\n'
    printf '  GOCACHE=%s \\\n' "$(quote_sh "/tmp/codexdock-gocache")"
    printf '  GOMODCACHE=%s \\\n' "$(quote_sh "/tmp/codexdock-gomodcache")"
    printf '  GOOS=%s \\\n' "$(quote_sh "linux")"
    printf '  GOARCH=%s \\\n' "$(quote_sh "$TARGET_ARCH")"
    printf '  OUT=%s \\\n' "$(quote_sh "$linux_binary")"
    printf '  ./scripts/build.sh\n'
    printf 'scp -P %s %s %s\n' "$(quote_sh "$SSH_PORT")" "$(quote_sh "$linux_binary")" "$(quote_sh "$stage_target:/tmp/codexdock")"
    printf 'ssh -p %s %s %s\n' "$(quote_sh "$SSH_PORT")" "$(quote_sh "$stage_target")" "$(quote_sh 'mkdir -p "$HOME/.local/bin" && mv /tmp/codexdock "$HOME/.local/bin/codexdock" && chmod 755 "$HOME/.local/bin/codexdock" && "$HOME/.local/bin/codexdock" version')"
  } >"$mac_stage"
  chmod +x "$mac_stage"

  {
    printf '#!/usr/bin/env sh\n'
    printf 'set -eu\n'
    printf 'CODEXDOCK_BIN=${CODEXDOCK_BIN:-"$HOME/.local/bin/codexdock"}\n'
    printf 'if [ ! -x "$CODEXDOCK_BIN" ]; then\n'
    printf '  CODEXDOCK_BIN=codexdock\n'
    printf 'fi\n'
    printf '"$CODEXDOCK_BIN" doctor --repair-plan --target-os linux --role codex-host --workspace %s%s\n' "$(quote_sh "$WORKSPACE")" "$ssh_key_arg"
  } >"$wsl_prepare_plan"
  chmod +x "$wsl_prepare_plan"

  {
    printf '#!/usr/bin/env sh\n'
    printf 'set -eu\n'
    printf 'CODEXDOCK_BIN=${CODEXDOCK_BIN:-"$HOME/.local/bin/codexdock"}\n'
    printf 'if [ ! -x "$CODEXDOCK_BIN" ]; then\n'
    printf '  CODEXDOCK_BIN=codexdock\n'
    printf 'fi\n'
    printf '"$CODEXDOCK_BIN" doctor --repair-plan --target-os linux --role codex-host --workspace %s%s\n' "$(quote_sh "$WORKSPACE")" "$ssh_key_arg"
    printf '"$CODEXDOCK_BIN" doctor --repair --yes --target-os linux --role codex-host --workspace %s%s\n' "$(quote_sh "$WORKSPACE")" "$ssh_key_arg"
  } >"$wsl_prepare"
  chmod +x "$wsl_prepare"

  {
    printf '#!/usr/bin/env sh\n'
    printf 'set -eu\n'
    printf 'cd %s\n' "$(quote_sh "$ROOT")"
    printf 'CODEXDOCK_TRENT_ENV_FILE=${CODEXDOCK_TRENT_ENV_FILE:-.dev-logs/trent-codexdock.env}\n'
    printf 'if [ -f "$CODEXDOCK_TRENT_ENV_FILE" ]; then\n'
    printf '  set -a\n'
    printf '  . "$CODEXDOCK_TRENT_ENV_FILE"\n'
    printf '  set +a\n'
    printf 'fi\n'
    printf './scripts/trent-finalize-e2e.sh %s\n' "$(quote_sh "$REPORT_DIR")"
  } >"$finalize"
  chmod +x "$finalize"

  {
    printf 'Remote E2E physical validation runbook\n\n'
    printf 'target architecture: %s\n\n' "$TARGET_ARCH"
    printf 'If SSH into WSL is not ready yet, install CodexDock from inside WSL first:\n'
    printf '  %s\n\n' "$wsl_install"
    printf 'Check WSL readiness without sudo:\n'
    printf '  %s\n\n' "$wsl_preflight"
    printf 'The WSL preflight report records the next local action as next=.\n\n'
    printf 'Inspect WSL prepare commands without running privileged steps:\n'
    printf '  %s\n\n' "$wsl_prepare_plan"
    printf 'Install the latest CodexDock binary into WSL from the Mac:\n'
    printf '  %s\n\n' "$mac_stage"
    printf 'Run inside WSL on the Codex host to prepare SSH, tmux, workspace, and managed internals:\n'
    printf '  %s\n\n' "$wsl_prepare"
    printf 'Run on the Mac to preflight local inputs:\n'
    printf '  %s\n\n' "$mac_preflight"
    printf 'Run on the Mac to execute the full validation:\n'
    printf '  %s\n\n' "$mac_run"
    printf 'Source TrentPlatform bootstrap env if it is not already exported:\n'
    printf '  . .dev-logs/trent-codexdock.env\n\n'
    printf 'After the full report validates, run on the Mac with TrentPlatform token env set:\n'
    printf '  %s\n\n' "$finalize"
    printf 'Report directory:\n'
    printf '  %s\n' "$REPORT_DIR"
  } >"$runbook"

  printf 'remote e2e runbook written\n'
  printf 'report directory: %s\n' "$REPORT_DIR"
}

write_preflight_context() {
  cat >"$REPORT_DIR/context.txt" <<EOF
network=$NETWORK
machine=$MACHINE
host=$HOST
control_url=$CONTROL_URL
ssh_user=$SSH_USER
ssh_port=$SSH_PORT
adopt=$ADOPT
prepare=$PREPARE
workspace=$WORKSPACE
session=$SESSION
agent=$AGENT
prompt=$PROMPT
log_lines=$LOG_LINES
ssh_authorized_key_set=$(if [ "$SSH_AUTHORIZED_KEY_PROVIDED" = "1" ]; then printf yes; else printf no; fi)
ssh_authorized_key_file_set=$(if [ "$SSH_AUTHORIZED_KEY_FILE_PROVIDED" = "1" ]; then printf yes; else printf no; fi)
require_scp=$REQUIRE_SCP
target_arch=$TARGET_ARCH
codexdock_bin=$CODEXDOCK_BIN
EOF
}

write_preflight_result() {
  status=$1
  exit_code=$2
  preflight=$3
  cat >"$REPORT_DIR/result.txt" <<EOF
status=$status
exit_code=$exit_code
network=$NETWORK
machine=$MACHINE
session=$SESSION
session_started=no
session_stopped=no
cleanup_attempted=no
cleanup_exit_code=not_applicable
preflight=$preflight
EOF
}

run_preflight() {
  ensure_report_dir
  missing=""
  invalid="none"

  identity_invalid=$(network_error)
  if [ -n "$identity_invalid" ]; then
    invalid=$(append_invalid "$invalid" "$identity_invalid")
  fi
  identity_invalid=$(machine_error)
  if [ -n "$identity_invalid" ]; then
    invalid=$(append_invalid "$invalid" "$identity_invalid")
  fi

  if [ "$ADOPT" != "1" ] && [ -z "$HOST" ]; then
    missing=$(append_name "$missing" CODEXDOCK_HOST)
  fi
  if [ -z "$SSH_USER" ]; then
    missing=$(append_name "$missing" CODEXDOCK_USER)
  fi
  adopt_invalid=$(adopt_flag_error)
  if [ -n "$adopt_invalid" ]; then
    invalid=$(append_invalid "$invalid" "$adopt_invalid")
  fi
  prepare_invalid=$(prepare_flag_error)
  if [ -n "$prepare_invalid" ]; then
    invalid=$(append_invalid "$invalid" "$prepare_invalid")
  fi
  require_scp_invalid=$(require_scp_flag_error)
  if [ -n "$require_scp_invalid" ]; then
    invalid=$(append_invalid "$invalid" "$require_scp_invalid")
  fi
  target_invalid=$(target_host_error)
  if [ -n "$target_invalid" ] && [ "$target_invalid" != "CODEXDOCK_HOST is required" ]; then
    invalid=$(append_invalid "$invalid" "$target_invalid")
  fi
  target_invalid=$(target_user_error)
  if [ -n "$target_invalid" ] && [ "$target_invalid" != "CODEXDOCK_USER is required" ]; then
    invalid=$(append_invalid "$invalid" "$target_invalid")
  fi
  ssh_port_invalid=$(ssh_port_error)
  if [ -n "$ssh_port_invalid" ]; then
    invalid=$(append_invalid "$invalid" "$ssh_port_invalid")
  fi
  log_lines_invalid=$(log_lines_error)
  if [ -n "$log_lines_invalid" ]; then
    invalid=$(append_invalid "$invalid" "$log_lines_invalid")
  fi
  target_arch_invalid=$(target_arch_error)
  if [ -n "$target_arch_invalid" ]; then
    invalid=$(append_invalid "$invalid" "$target_arch_invalid")
  fi
  control_url_invalid=$(control_url_error)
  if [ -n "$control_url_invalid" ]; then
    invalid=$(append_invalid "$invalid" "$control_url_invalid")
  fi
  workspace_invalid=$(workspace_error)
  if [ -n "$workspace_invalid" ]; then
    invalid=$(append_invalid "$invalid" "$workspace_invalid")
  fi
  session_invalid=$(session_error)
  if [ -n "$session_invalid" ]; then
    invalid=$(append_invalid "$invalid" "$session_invalid")
  fi
  agent_invalid=$(agent_error)
  if [ -n "$agent_invalid" ]; then
    invalid=$(append_invalid "$invalid" "$agent_invalid")
  fi
  prompt_invalid=$(prompt_error)
  if [ -n "$prompt_invalid" ]; then
    invalid=$(append_invalid "$invalid" "$prompt_invalid")
  fi

  go_status=$(command_status go)
  ssh_status=$(command_status ssh)
  scp_status=$(command_status scp)
  private_network_status=$(command_status tailscale)
  codexdock_bin_status=not_set
  if [ "$CODEXDOCK_BIN_PROVIDED" = "1" ]; then
    if [ -z "$CODEXDOCK_BIN" ]; then
      codexdock_bin_status=invalid
      invalid=$(append_invalid "$invalid" "CODEXDOCK_BIN cannot be blank")
    elif [ ! -f "$CODEXDOCK_BIN" ]; then
      codexdock_bin_status=missing
      invalid=$(append_invalid "$invalid" "CODEXDOCK_BIN is not executable")
    elif [ ! -x "$CODEXDOCK_BIN" ]; then
      codexdock_bin_status=not_executable
      invalid=$(append_invalid "$invalid" "CODEXDOCK_BIN is not executable")
    else
      codexdock_bin_status=executable
    fi
  fi
  if [ "$CODEXDOCK_BIN_PROVIDED" = "0" ] && [ "$go_status" != "yes" ]; then
    missing=$(append_name "$missing" go)
  fi
  if [ "$ssh_status" != "yes" ]; then
    missing=$(append_name "$missing" ssh)
  fi
  if [ "$REQUIRE_SCP" = "1" ] && [ "$scp_status" != "yes" ]; then
    missing=$(append_name "$missing" scp)
  fi
  if [ "$ADOPT" = "1" ] && [ "$private_network_status" != "yes" ]; then
    missing=$(append_name "$missing" tailscale)
  fi

  ssh_key_file_status=not_set
  ssh_key_invalid=$(ssh_authorized_key_error)
  if [ -n "$ssh_key_invalid" ]; then
    invalid=$(append_invalid "$invalid" "$ssh_key_invalid")
  fi
  ssh_key_file_invalid=$(ssh_authorized_key_file_path_error)
  if [ -n "$ssh_key_file_invalid" ]; then
    ssh_key_file_status=invalid
    invalid=$(append_invalid "$invalid" "$ssh_key_file_invalid")
  fi
  if [ -n "$SSH_AUTHORIZED_KEY" ] && [ -n "$SSH_AUTHORIZED_KEY_FILE" ]; then
    invalid=$(append_invalid "$invalid" "set either CODEXDOCK_SSH_AUTHORIZED_KEY or CODEXDOCK_SSH_AUTHORIZED_KEY_FILE, not both")
  elif [ -n "$SSH_AUTHORIZED_KEY_FILE" ] && [ -z "$ssh_key_file_invalid" ]; then
    if [ ! -f "$SSH_AUTHORIZED_KEY_FILE" ]; then
      ssh_key_file_status=missing
      invalid=$(append_invalid "$invalid" "CODEXDOCK_SSH_AUTHORIZED_KEY_FILE does not exist")
    elif ssh_authorized_key_file_content_is_blank; then
      ssh_key_file_status=empty
      invalid=$(append_invalid "$invalid" "CODEXDOCK_SSH_AUTHORIZED_KEY_FILE is empty")
    else
      ssh_key_file_status=readable
    fi
  fi

  if [ -z "$missing" ]; then
    missing=none
  fi

  preflight_status=success
  exit_code=0
  preflight=passed
  if [ "$missing" != "none" ] || [ "$invalid" != "none" ]; then
    preflight_status=failure
    exit_code=2
    preflight=failed
  fi

  write_preflight_context
  cat >"$REPORT_DIR/preflight.txt" <<EOF
status=$preflight_status
missing=$missing
invalid=$invalid
local_go=$go_status
local_codexdock_bin=$codexdock_bin_status
local_ssh=$ssh_status
local_scp=$scp_status
scp_required=$(if [ "$REQUIRE_SCP" = "1" ]; then printf yes; else printf no; fi)
private_network_client=$private_network_status
adopt_requires_private_network_client=$(if [ "$ADOPT" = "1" ]; then printf yes; else printf no; fi)
ssh_authorized_key_file=$ssh_key_file_status
report_dir=$REPORT_DIR
EOF
  write_preflight_result "$preflight_status" "$exit_code" "$preflight"

  if [ "$exit_code" -eq 0 ]; then
    printf 'remote e2e preflight ok\n'
  else
    printf 'remote e2e preflight failed\n'
  fi
  printf 'report directory: %s\n' "$REPORT_DIR"
  return "$exit_code"
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  usage
  exit 0
fi

if [ "${1:-}" = "--print-plan" ]; then
  print_plan
  exit 0
fi

if [ "${1:-}" = "--write-runbook" ]; then
  write_runbook
  exit 0
fi

PREFLIGHT=0
if [ "${1:-}" = "--preflight" ]; then
  PREFLIGHT=1
  shift
fi

if [ "$#" -gt 0 ]; then
  usage >&2
  exit 2
fi

if [ "$PREFLIGHT" = "1" ]; then
  run_preflight
  exit $?
fi

require_valid_flags
require_valid_identity
require_target_inputs
require_valid_ssh_port
require_valid_log_lines
require_valid_control_url
require_valid_profile
require_valid_codexdock_bin
require_supported_target_arch
require_valid_ssh_authorized_key_sources

if [ -n "$SSH_AUTHORIZED_KEY" ] && [ -n "$SSH_AUTHORIZED_KEY_FILE" ]; then
  echo "set either CODEXDOCK_SSH_AUTHORIZED_KEY or CODEXDOCK_SSH_AUTHORIZED_KEY_FILE, not both" >&2
  exit 2
fi

if [ -n "$SSH_AUTHORIZED_KEY_FILE" ]; then
  if [ ! -f "$SSH_AUTHORIZED_KEY_FILE" ]; then
    echo "CODEXDOCK_SSH_AUTHORIZED_KEY_FILE does not exist: $SSH_AUTHORIZED_KEY_FILE" >&2
    exit 2
  fi
  SSH_AUTHORIZED_KEY=$(trim_value "$(sed -n '1p' "$SSH_AUTHORIZED_KEY_FILE")")
  if [ -z "$SSH_AUTHORIZED_KEY" ]; then
    echo "CODEXDOCK_SSH_AUTHORIZED_KEY_FILE is empty: $SSH_AUTHORIZED_KEY_FILE" >&2
    exit 2
  fi
fi

TMP=${TMPDIR:-/tmp}
WORK=$(mktemp -d "$TMP/codexdock-e2e.XXXXXX")
SESSION_STARTED=0
SESSION_STOPPED=0
CLEANUP_ATTEMPTED=0
CLEANUP_EXIT_CODE=not_applicable
cleanup() {
  status=$?
  cleanup_remote_session
  write_result "$status"
  rm -rf "$WORK"
  exit "$status"
}
trap cleanup EXIT INT TERM

BIN="$WORK/codexdock"
HOME_DIR="$WORK/home"
mkdir -p "$HOME_DIR"

if [ -n "${CODEXDOCK_REPORT_DIR:-}" ]; then
  REPORT_DIR=$CODEXDOCK_REPORT_DIR
else
  REPORT_DIR="$ROOT/.dev-logs/e2e-remote/$(date -u +%Y%m%dT%H%M%SZ)"
fi
mkdir -p "$REPORT_DIR"

write_context() {
  cat >"$REPORT_DIR/context.txt" <<EOF
network=$NETWORK
machine=$MACHINE
host=$HOST
control_url=$CONTROL_URL
ssh_user=$SSH_USER
ssh_port=$SSH_PORT
adopt=$ADOPT
prepare=$PREPARE
workspace=$WORKSPACE
session=$SESSION
agent=$AGENT
prompt=$PROMPT
log_lines=$LOG_LINES
ssh_authorized_key_set=$(if [ "$SSH_AUTHORIZED_KEY_PROVIDED" = "1" ]; then printf yes; else printf no; fi)
ssh_authorized_key_file_set=$(if [ "$SSH_AUTHORIZED_KEY_FILE_PROVIDED" = "1" ]; then printf yes; else printf no; fi)
require_scp=$REQUIRE_SCP
target_arch=$TARGET_ARCH
codexdock_bin=$CODEXDOCK_BIN
EOF
}

run_step() {
  step=$1
  shift
  printf '%s\n' "$*" >"$REPORT_DIR/$step.cmd"
  if "$@" >"$REPORT_DIR/$step.out" 2>"$REPORT_DIR/$step.err"; then
    return 0
  fi
  status=$?
  printf 'remote e2e step failed: %s\n' "$step" >&2
  printf 'report directory: %s\n' "$REPORT_DIR" >&2
  if [ -s "$REPORT_DIR/$step.err" ]; then
    printf '\n%s stderr:\n' "$step" >&2
    sed -n '1,120p' "$REPORT_DIR/$step.err" >&2
  fi
  if [ -s "$REPORT_DIR/$step.out" ]; then
    printf '\n%s stdout:\n' "$step" >&2
    sed -n '1,120p' "$REPORT_DIR/$step.out" >&2
  fi
  exit "$status"
}

cleanup_remote_session() {
  if [ "${SESSION_STARTED:-0}" != "1" ] || [ "${SESSION_STOPPED:-0}" = "1" ]; then
    return 0
  fi
  if [ -z "${REPORT_DIR:-}" ] || [ -z "${BIN:-}" ] || [ ! -x "$BIN" ]; then
    return 0
  fi
  CLEANUP_ATTEMPTED=1
  printf 'env HOME=%s %s stop %s --force\n' "$HOME_DIR" "$BIN" "$MACHINE" >"$REPORT_DIR/cleanup_stop.cmd"
  set +e
  env HOME="$HOME_DIR" "$BIN" stop "$MACHINE" --force >"$REPORT_DIR/cleanup_stop.out" 2>"$REPORT_DIR/cleanup_stop.err"
  cleanup_status=$?
  set -e
  CLEANUP_EXIT_CODE=$cleanup_status
  if [ "$cleanup_status" -eq 0 ]; then
    SESSION_STOPPED=1
  fi
}

write_result() {
  status=$1
  if [ -z "${REPORT_DIR:-}" ]; then
    return 0
  fi
  result_status=failure
  if [ "$status" -eq 0 ]; then
    result_status=success
  fi
  cat >"$REPORT_DIR/result.txt" <<EOF
status=$result_status
exit_code=$status
network=$NETWORK
machine=$MACHINE
session=$SESSION
session_started=$(yes_no "$SESSION_STARTED")
session_stopped=$(yes_no "$SESSION_STOPPED")
cleanup_attempted=$(yes_no "$CLEANUP_ATTEMPTED")
cleanup_exit_code=$CLEANUP_EXIT_CODE
EOF
}

yes_no() {
  if [ "${1:-0}" = "1" ]; then
    printf yes
  else
    printf no
  fi
}

GOCACHE=${GOCACHE:-/tmp/codexdock-gocache}
GOMODCACHE=${GOMODCACHE:-/tmp/codexdock-gomodcache}
VERSION=${VERSION:-e2e}
COMMIT=${COMMIT:-e2e}
BUILD_DATE=${BUILD_DATE:-1970-01-01T00:00:00Z}

write_context
if [ -n "$CODEXDOCK_BIN" ]; then
  BIN=$CODEXDOCK_BIN
  run_step build env CODEXDOCK_BIN="$CODEXDOCK_BIN" "$BIN" version
else
  run_step build env GOCACHE="$GOCACHE" GOMODCACHE="$GOMODCACHE" VERSION="$VERSION" COMMIT="$COMMIT" BUILD_DATE="$BUILD_DATE" OUT="$BIN" "$ROOT/scripts/build.sh"
fi

if [ "$ADOPT" = "1" ]; then
  if [ -n "$CONTROL_URL" ]; then
    run_step create env HOME="$HOME_DIR" "$BIN" create "$NETWORK" --control-url "$CONTROL_URL"
  else
    run_step create env HOME="$HOME_DIR" "$BIN" create "$NETWORK"
  fi
  run_step adopt env HOME="$HOME_DIR" "$BIN" adopt "$MACHINE" \
    --ssh-user "$SSH_USER" \
    --ssh-port "$SSH_PORT" \
    --workspace "$WORKSPACE" \
    --session "$SESSION" \
    --agent "$AGENT"
else
  if [ -n "$CONTROL_URL" ]; then
    run_step init env HOME="$HOME_DIR" "$BIN" init \
      --network "$NETWORK" \
      --machine "$MACHINE" \
      --host "$HOST" \
      --ssh-user "$SSH_USER" \
      --ssh-port "$SSH_PORT" \
      --control-url "$CONTROL_URL" \
      --workspace "$WORKSPACE" \
      --session "$SESSION" \
      --agent "$AGENT"
  else
    run_step init env HOME="$HOME_DIR" "$BIN" init \
      --network "$NETWORK" \
      --machine "$MACHINE" \
      --host "$HOST" \
      --ssh-user "$SSH_USER" \
      --ssh-port "$SSH_PORT" \
      --workspace "$WORKSPACE" \
      --session "$SESSION" \
      --agent "$AGENT"
  fi
fi

if [ "$PREPARE" = "1" ]; then
  if [ -n "$SSH_AUTHORIZED_KEY" ]; then
    run_step prepare env HOME="$HOME_DIR" "$BIN" doctor "$MACHINE" --repair --yes --target-os linux --role codex-host --ssh-authorized-key "$SSH_AUTHORIZED_KEY"
  else
    run_step prepare env HOME="$HOME_DIR" "$BIN" doctor "$MACHINE" --repair --yes --target-os linux --role codex-host
  fi
fi

run_step doctor env HOME="$HOME_DIR" "$BIN" doctor "$MACHINE"
run_step doctor_all env HOME="$HOME_DIR" "$BIN" doctor --all
run_step start env HOME="$HOME_DIR" "$BIN" start "$MACHINE"
SESSION_STARTED=1
if [ "${CODEXDOCK_E2E_FAIL_AFTER_START:-0}" = "1" ]; then
  printf 'remote e2e forced failure after start\n' >&2
  exit 1
fi
run_step sessions env HOME="$HOME_DIR" "$BIN" sessions "$MACHINE"
run_step sessions_all env HOME="$HOME_DIR" "$BIN" sessions
run_step send env HOME="$HOME_DIR" "$BIN" send "$MACHINE" "$PROMPT"
run_step logs env HOME="$HOME_DIR" "$BIN" logs "$MACHINE" --lines "$LOG_LINES"
run_step stop env HOME="$HOME_DIR" "$BIN" stop "$MACHINE" --force
SESSION_STOPPED=1
run_step sessions_after_stop env HOME="$HOME_DIR" "$BIN" sessions "$MACHINE"

printf 'remote e2e ok\n'
printf 'report directory: %s\n' "$REPORT_DIR"
