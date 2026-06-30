#!/usr/bin/env sh
set -eu

usage() {
  cat <<EOF
Usage: $0 [--full] <report-dir>

Options:
  --full  Require successful non-preflight remote E2E step artifacts
EOF
}

FULL=0
if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  usage
  exit 0
fi

if [ "${1:-}" = "--full" ]; then
  FULL=1
  shift
fi

if [ "$#" -ne 1 ]; then
  usage >&2
  exit 2
fi

REPORT_DIR=$1
RESULT_FILE="$REPORT_DIR/result.txt"

if [ ! -d "$REPORT_DIR" ]; then
  echo "report directory not found: $REPORT_DIR" >&2
  exit 2
fi

if [ ! -f "$RESULT_FILE" ]; then
  echo "result.txt not found in report directory: $REPORT_DIR" >&2
  exit 2
fi

field() {
  sed -n "s/^$1=//p" "$RESULT_FILE" | sed -n '1p'
}

context_field() {
  sed -n "s/^$1=//p" "$CONTEXT_FILE" | sed -n '1p'
}

require_contains() {
  file=$1
  text=$2
  if ! grep -F "$text" "$file" >/dev/null; then
    echo "remote E2E report artifact did not contain expected text: $(basename "$file")" >&2
    exit 2
  fi
}

require_command_token() {
  step=$1
  token=$2
  file="$REPORT_DIR/$step.cmd"
  line=$(sed -n '1p' "$file")
  case " $line " in
    *" $token "*) ;;
    *)
      echo "remote E2E report command artifact does not contain expected token: $step.cmd $token" >&2
      exit 2
      ;;
  esac
}

require_command_text() {
  step=$1
  text=$2
  file="$REPORT_DIR/$step.cmd"
  if ! grep -F -- "$text" "$file" >/dev/null; then
    echo "remote E2E report command artifact did not contain expected text: $step.cmd" >&2
    exit 2
  fi
}

require_command_words() {
  step=$1
  text=$2
  file="$REPORT_DIR/$step.cmd"
  line=$(sed -n '1p' "$file")
  case " $line " in
    *" $text "*) ;;
    *)
      echo "remote E2E report command artifact did not contain expected text: $step.cmd" >&2
      exit 2
      ;;
  esac
}

require_build_artifact() {
  if grep -F "build.sh" "$REPORT_DIR/build.cmd" >/dev/null; then
    context_bin=$(context_field codexdock_bin)
    if [ -n "$context_bin" ]; then
      echo "remote E2E report context codexdock_bin must be blank for source build reports" >&2
      exit 2
    fi
    return 0
  fi
  context_bin=$(context_field codexdock_bin)
  if [ -z "$context_bin" ]; then
    echo "remote E2E report context codexdock_bin cannot be blank for binary build reports" >&2
    exit 2
  fi
  require_command_text build "CODEXDOCK_BIN="
  require_command_text build "CODEXDOCK_BIN=$context_bin"
  require_command_token build version
  require_contains "$REPORT_DIR/build.out" "codexdock"
}

field_count() {
  file=$1
  name=$2
  awk -v field="$name" 'index($0, field "=") == 1 { count++ } END { print count + 0 }' "$file"
}

require_context_field_once() {
  name=$1
  count=$(field_count "$CONTEXT_FILE" "$name")
  if [ "$count" -eq 0 ]; then
    echo "remote E2E report artifact did not contain expected text: context.txt" >&2
    exit 2
  fi
  if [ "$count" -gt 1 ]; then
    echo "remote E2E report context field appears more than once: $name" >&2
    exit 2
  fi
}

require_result_field_once() {
  name=$1
  count=$(field_count "$RESULT_FILE" "$name")
  if [ "$count" -eq 0 ]; then
    echo "remote E2E report result field is missing: $name" >&2
    exit 2
  fi
  if [ "$count" -gt 1 ]; then
    echo "remote E2E report result field appears more than once: $name" >&2
    exit 2
  fi
}

require_result_not_blank() {
  name=$1
  value=$(field "$name")
  case "$value" in
    *[![:space:]]*) ;;
    *)
      echo "remote E2E report result $name cannot be blank" >&2
      exit 2
      ;;
  esac
}

require_context_matches_result() {
  name=$1
  expected=$2
  actual=$(context_field "$name")
  if [ "$actual" != "$expected" ]; then
    echo "remote E2E report context $name does not match result: ${actual:-missing} != ${expected:-missing}" >&2
    exit 2
  fi
}

require_context_target_arch_supported() {
  target_arch=$(context_field target_arch)
  case "$target_arch" in
    amd64|arm64) ;;
    *)
      echo "remote E2E report context target_arch is unsupported: ${target_arch:-missing}" >&2
      exit 2
      ;;
  esac
}

require_context_positive_integer() {
  name=$1
  value=$(context_field "$name")
  case "$value" in
    ''|*[!0-9]*)
      echo "remote E2E report context $name must be a positive integer: ${value:-missing}" >&2
      exit 2
      ;;
  esac
  if [ "$value" -eq 0 ]; then
    echo "remote E2E report context $name must be a positive integer: $value" >&2
    exit 2
  fi
}

require_context_zero_or_one() {
  name=$1
  value=$(context_field "$name")
  case "$value" in
    0|1) ;;
    *)
      echo "remote E2E report context $name must be 0 or 1: ${value:-missing}" >&2
      exit 2
      ;;
  esac
}

require_context_yes_or_no() {
  name=$1
  value=$(context_field "$name")
  case "$value" in
    yes|no) ;;
    *)
      echo "remote E2E report context $name must be yes or no: ${value:-missing}" >&2
      exit 2
      ;;
  esac
}

require_context_not_blank() {
  name=$1
  value=$(context_field "$name")
  case "$value" in
    *[![:space:]]*) ;;
    *)
      echo "remote E2E report context $name cannot be blank" >&2
      exit 2
      ;;
  esac
}

require_context_session_name() {
  value=$(context_field session)
  case "$value" in
    ''|*[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-]*)
      echo "remote E2E report context session must contain only letters, numbers, underscores, or hyphens" >&2
      exit 2
      ;;
  esac
}

require_result_yes_or_no() {
  name=$1
  value=$(field "$name")
  case "$value" in
    yes|no) ;;
    *)
      echo "remote E2E report result $name must be yes or no: ${value:-missing}" >&2
      exit 2
      ;;
  esac
}

require_result_cleanup_consistent() {
  cleanup_attempted=$(field cleanup_attempted)
  cleanup_exit_code=$(field cleanup_exit_code)
  if [ "$cleanup_attempted" = "no" ]; then
    if [ "$cleanup_exit_code" != "not_applicable" ]; then
      echo "remote E2E report result cleanup_exit_code must be not_applicable when cleanup_attempted=no: ${cleanup_exit_code:-missing}" >&2
      exit 2
    fi
    return 0
  fi
  case "$cleanup_exit_code" in
    ''|*[!0-9]*)
      echo "remote E2E report result cleanup_exit_code must be numeric when cleanup_attempted=yes: ${cleanup_exit_code:-missing}" >&2
      exit 2
      ;;
  esac
  if [ "$cleanup_exit_code" -ne 0 ]; then
    echo "remote E2E report result cleanup_exit_code must be 0 when cleanup_attempted=yes: $cleanup_exit_code" >&2
    exit 2
  fi
}

for result_field in status exit_code network machine session; do
  require_result_field_once "$result_field"
done
for result_field in network machine session; do
  require_result_not_blank "$result_field"
done

STATUS=$(field status)
EXIT_CODE=$(field exit_code)
PREFLIGHT=$(field preflight)
SESSION_STARTED=$(field session_started)
SESSION_STOPPED=$(field session_stopped)
NETWORK=$(field network)
MACHINE=$(field machine)
SESSION=$(field session)

if [ "$STATUS" != "success" ]; then
  echo "remote E2E report is not successful: status=${STATUS:-missing}" >&2
  exit 2
fi

if [ "$EXIT_CODE" != "0" ]; then
  echo "remote E2E report has non-zero exit_code=${EXIT_CODE:-missing}" >&2
  exit 2
fi

if [ "$FULL" = "0" ]; then
  printf 'remote E2E report ok\n'
  exit 0
fi

for result_field in session_started session_stopped cleanup_attempted cleanup_exit_code; do
  require_result_field_once "$result_field"
done
require_result_yes_or_no cleanup_attempted
require_result_cleanup_consistent

if [ -n "$PREFLIGHT" ]; then
  echo "remote E2E report is preflight-only; refusing full validation" >&2
  exit 2
fi

if [ "$SESSION_STARTED" != "yes" ]; then
  echo "remote E2E report did not start a session: session_started=${SESSION_STARTED:-missing}" >&2
  exit 2
fi

if [ "$SESSION_STOPPED" != "yes" ]; then
  echo "remote E2E report did not stop the session: session_stopped=${SESSION_STOPPED:-missing}" >&2
  exit 2
fi

CONTEXT_FILE="$REPORT_DIR/context.txt"
if [ ! -f "$CONTEXT_FILE" ]; then
  echo "remote E2E report is missing required artifact: context.txt" >&2
  exit 2
fi
for context_field in \
  network \
  machine \
  host \
  control_url \
  ssh_user \
  ssh_port \
  adopt \
  prepare \
  workspace \
  session \
  agent \
  prompt \
  log_lines \
  ssh_authorized_key_set \
  ssh_authorized_key_file_set \
  require_scp \
  target_arch \
  codexdock_bin
do
  require_context_field_once "$context_field"
done
require_context_matches_result network "$NETWORK"
require_context_matches_result machine "$MACHINE"
require_context_matches_result session "$SESSION"
require_context_target_arch_supported
require_context_positive_integer ssh_port
require_context_positive_integer log_lines
require_context_zero_or_one require_scp
require_context_yes_or_no ssh_authorized_key_set
require_context_yes_or_no ssh_authorized_key_file_set
require_context_not_blank network
require_context_not_blank machine
require_context_not_blank ssh_user
require_context_not_blank workspace
require_context_session_name
require_context_not_blank agent
require_context_not_blank prompt
context_adopt=$(context_field adopt)
if [ "$context_adopt" = "0" ]; then
  require_context_not_blank host
fi

required_steps="build doctor doctor_all start sessions sessions_all send logs stop sessions_after_stop"
if [ -f "$REPORT_DIR/init.cmd" ] && [ -f "$REPORT_DIR/adopt.cmd" ]; then
  echo "remote E2E report has both init.cmd and adopt.cmd" >&2
  exit 2
elif [ -f "$REPORT_DIR/init.cmd" ]; then
  context_adopt=$(context_field adopt)
  if [ "$context_adopt" != "0" ]; then
    echo "remote E2E report context adopt does not match artifacts: ${context_adopt:-missing} != 0" >&2
    exit 2
  fi
  required_steps="build init doctor doctor_all start sessions sessions_all send logs stop sessions_after_stop"
elif [ -f "$REPORT_DIR/adopt.cmd" ]; then
  context_adopt=$(context_field adopt)
  if [ "$context_adopt" != "1" ]; then
    echo "remote E2E report context adopt does not match artifacts: ${context_adopt:-missing} != 1" >&2
    exit 2
  fi
  required_steps="build create adopt doctor doctor_all start sessions sessions_all send logs stop sessions_after_stop"
else
  echo "remote E2E report is missing required artifact: init.cmd or adopt.cmd" >&2
  exit 2
fi

context_prepare=$(context_field prepare)
if [ -f "$REPORT_DIR/prepare.cmd" ]; then
  if [ "$context_prepare" != "1" ]; then
    echo "remote E2E report context prepare does not match artifacts: ${context_prepare:-missing} != 1" >&2
    exit 2
  fi
  required_steps="$required_steps prepare"
else
  if [ "$context_prepare" != "0" ]; then
    echo "remote E2E report context prepare does not match artifacts: ${context_prepare:-missing} != 0" >&2
    exit 2
  fi
fi

if [ "$(field cleanup_attempted)" = "yes" ]; then
  required_steps="$required_steps cleanup_stop"
fi

for step in $required_steps; do
  for suffix in cmd out err; do
    file="$REPORT_DIR/$step.$suffix"
    if [ ! -f "$file" ]; then
      echo "remote E2E report is missing required artifact: $step.$suffix" >&2
      exit 2
    fi
    if [ "$suffix" = "cmd" ] && [ ! -s "$file" ]; then
      echo "remote E2E report command artifact is empty: $step.$suffix" >&2
      exit 2
    fi
  done
done

require_build_artifact
if [ -f "$REPORT_DIR/init.cmd" ]; then
  require_command_token init init
  require_command_words init "--network $(context_field network)"
  require_command_words init "--host $(context_field host)"
  require_command_words init "--ssh-user $(context_field ssh_user)"
  require_command_words init "--ssh-port $(context_field ssh_port)"
  context_control_url=$(context_field control_url)
  if [ -n "$context_control_url" ]; then
    require_command_words init "--control-url $context_control_url"
  fi
  require_command_words init "--workspace $(context_field workspace)"
  require_command_words init "--session $(context_field session)"
  require_command_words init "--agent $(context_field agent)"
fi
if [ -f "$REPORT_DIR/create.cmd" ]; then
  require_command_token create create
  require_command_words create "$(context_field network)"
  context_control_url=$(context_field control_url)
  if [ -n "$context_control_url" ]; then
    require_command_words create "--control-url $context_control_url"
  fi
fi
if [ -f "$REPORT_DIR/adopt.cmd" ]; then
  require_command_token adopt adopt
  require_command_words adopt "--ssh-user $(context_field ssh_user)"
  require_command_words adopt "--ssh-port $(context_field ssh_port)"
  require_command_words adopt "--workspace $(context_field workspace)"
  require_command_words adopt "--session $(context_field session)"
  require_command_words adopt "--agent $(context_field agent)"
fi
if [ -f "$REPORT_DIR/prepare.cmd" ]; then
  require_command_token prepare doctor
  require_command_token prepare --repair
  if [ "$(context_field ssh_authorized_key_set)" = "yes" ] || [ "$(context_field ssh_authorized_key_file_set)" = "yes" ]; then
    require_command_token prepare --ssh-authorized-key
  fi
fi
require_command_token doctor doctor
require_command_token doctor_all doctor
require_command_token doctor_all --all
require_command_token start start
require_command_token sessions sessions
require_command_token sessions_all sessions
require_command_token send send
require_command_token logs logs
require_command_token stop stop
require_command_token sessions_after_stop sessions
require_command_words logs "--lines $(context_field log_lines)"
require_command_words send "$(context_field prompt)"
if [ -f "$REPORT_DIR/cleanup_stop.cmd" ]; then
  require_command_token cleanup_stop stop
  require_command_token cleanup_stop "$MACHINE"
fi
for targeted_step in init adopt prepare doctor start sessions send logs stop sessions_after_stop; do
  if [ -f "$REPORT_DIR/$targeted_step.cmd" ]; then
    require_command_token "$targeted_step" "$MACHINE"
  fi
done

if [ -z "$MACHINE" ]; then
  MACHINE=unknown
fi
if [ -z "$SESSION" ]; then
  SESSION=unknown
fi

require_contains "$REPORT_DIR/doctor.out" "ok can connect to $MACHINE"
require_contains "$REPORT_DIR/doctor.out" "ok remote tmux found"
require_contains "$REPORT_DIR/doctor.out" "ok remote"
require_contains "$REPORT_DIR/doctor.out" "ok workspace exists"
require_contains "$REPORT_DIR/doctor_all.out" "ok can connect to $MACHINE"
require_contains "$REPORT_DIR/start.out" "Codex session '$SESSION'"
require_contains "$REPORT_DIR/sessions.out" "$MACHINE"
require_contains "$REPORT_DIR/sessions.out" "$SESSION"
require_contains "$REPORT_DIR/sessions.out" "running"
require_contains "$REPORT_DIR/sessions_all.out" "$MACHINE"
require_contains "$REPORT_DIR/sessions_all.out" "$SESSION"
require_contains "$REPORT_DIR/sessions_all.out" "running"
require_contains "$REPORT_DIR/send.out" "Sent prompt to $SESSION on $MACHINE."
if [ ! -s "$REPORT_DIR/logs.out" ]; then
  echo "remote E2E report artifact is empty: logs.out" >&2
  exit 2
fi
require_contains "$REPORT_DIR/stop.out" "Stopped Codex session '$SESSION' on $MACHINE."
require_contains "$REPORT_DIR/stop.err" "warning: Codex session '$SESSION' on $MACHINE will be killed."
require_contains "$REPORT_DIR/sessions_after_stop.out" "No tmux sessions found on $MACHINE."

printf 'remote E2E full report ok\n'
