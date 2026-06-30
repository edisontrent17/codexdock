#!/usr/bin/env sh
set -eu

usage() {
  cat <<EOF
Usage: CODEXDOCK_TRENT_TOKEN=<token> CODEXDOCK_TRENT_PROJECT=<project-id> $0 <report-dir>

Environment:
  CODEXDOCK_TRENT_TOKEN       TrentPlatform bearer token
  CODEXDOCK_TRENT_TOKEN_FILE  JSON file containing personalAccessToken or accessToken
  CODEXDOCK_TRENT_PROJECT     TrentPlatform CodexDock.Project record id
  CODEXDOCK_TRENT_BASE_URL    TrentPlatform base URL (default: https://trentplatform.trentsoftware.in)
  CODEXDOCK_TRENT_NAMESPACE   Metadata namespace (default: CodexDock)
  CODEXDOCK_TRENT_OBJECT      Artifact object name (default: Artifact)
  CODEXDOCK_TRENT_TITLE       Artifact title override
EOF
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  usage
  exit 0
fi

if [ "$#" -ne 1 ]; then
  usage >&2
  exit 2
fi

REPORT_DIR=$1
RESULT_FILE="$REPORT_DIR/result.txt"
CONTEXT_FILE="$REPORT_DIR/context.txt"
PREFLIGHT_FILE="$REPORT_DIR/preflight.txt"

if [ ! -d "$REPORT_DIR" ]; then
  echo "report directory not found: $REPORT_DIR" >&2
  exit 2
fi

if [ ! -f "$RESULT_FILE" ]; then
  echo "result.txt not found in report directory: $REPORT_DIR" >&2
  exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required to build the TrentPlatform artifact payload" >&2
  exit 2
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "curl is required to publish the TrentPlatform artifact" >&2
  exit 2
fi

TOKEN=${CODEXDOCK_TRENT_TOKEN:-}
if [ -z "$TOKEN" ] && [ -n "${CODEXDOCK_TRENT_TOKEN_FILE:-}" ]; then
  if [ ! -f "$CODEXDOCK_TRENT_TOKEN_FILE" ]; then
    echo "CODEXDOCK_TRENT_TOKEN_FILE not found: $CODEXDOCK_TRENT_TOKEN_FILE" >&2
    exit 2
  fi
  TOKEN=$(jq -r '.personalAccessToken // .accessToken // empty' "$CODEXDOCK_TRENT_TOKEN_FILE")
fi

if [ -z "$TOKEN" ]; then
  echo "CODEXDOCK_TRENT_TOKEN or CODEXDOCK_TRENT_TOKEN_FILE is required" >&2
  exit 2
fi

PROJECT=${CODEXDOCK_TRENT_PROJECT:-}
if [ -z "$PROJECT" ]; then
  echo "CODEXDOCK_TRENT_PROJECT is required" >&2
  exit 2
fi

BASE_URL=${CODEXDOCK_TRENT_BASE_URL:-https://trentplatform.trentsoftware.in}
NAMESPACE=${CODEXDOCK_TRENT_NAMESPACE:-CodexDock}
OBJECT=${CODEXDOCK_TRENT_OBJECT:-Artifact}
ARTIFACT_TYPE=${CODEXDOCK_TRENT_ARTIFACT_TYPE:-plan}
ARTIFACT_STATUS=${CODEXDOCK_TRENT_STATUS:-active}

field() {
  sed -n "s/^$1=//p" "$RESULT_FILE" | sed -n '1p'
}

STATUS=$(field status)
EXIT_CODE=$(field exit_code)
NETWORK=$(field network)
MACHINE=$(field machine)
SESSION=$(field session)
SESSION_STARTED=$(field session_started)
SESSION_STOPPED=$(field session_stopped)
CLEANUP_ATTEMPTED=$(field cleanup_attempted)
CLEANUP_EXIT_CODE=$(field cleanup_exit_code)
PREFLIGHT=$(field preflight)

if [ -z "$STATUS" ]; then
  STATUS=unknown
fi
if [ -z "$EXIT_CODE" ]; then
  EXIT_CODE=unknown
fi
if [ -z "$NETWORK" ]; then
  NETWORK=unknown
fi
if [ -z "$MACHINE" ]; then
  MACHINE=unknown
fi
if [ -z "$SESSION" ]; then
  SESSION=unknown
fi
if [ -z "$SESSION_STARTED" ]; then
  SESSION_STARTED=unknown
fi
if [ -z "$SESSION_STOPPED" ]; then
  SESSION_STOPPED=unknown
fi
if [ -z "$CLEANUP_ATTEMPTED" ]; then
  CLEANUP_ATTEMPTED=unknown
fi
if [ -z "$CLEANUP_EXIT_CODE" ]; then
  CLEANUP_EXIT_CODE=unknown
fi

file_size() {
  set -- $(wc -c <"$1")
  printf '%s' "$1"
}

redact_command_line() {
  awk '
    function append(value) {
      if (out == "") {
        out = value
      } else {
        out = out " " value
      }
    }
    {
      out = ""
      redacting = 0
      for (i = 1; i <= NF; i++) {
        if ($i == "--ssh-authorized-key" || $i == "--enrollment-key") {
          append($i)
          append("<redacted>")
          redacting = 1
          continue
        }
        if ($i ~ /^--ssh-authorized-key=/) {
          append("--ssh-authorized-key=<redacted>")
          redacting = 1
          continue
        }
        if ($i ~ /^--enrollment-key=/) {
          append("--enrollment-key=<redacted>")
          redacting = 0
          continue
        }
        if (redacting == 1) {
          if ($i ~ /^--/) {
            redacting = 0
          } else {
            continue
          }
        }
        append($i)
      }
      print out
    }
  '
}

print_command_artifacts() {
  found=0
  for step in build create init adopt prepare doctor doctor_all start sessions sessions_all send logs stop cleanup_stop sessions_after_stop; do
    cmd_file="$REPORT_DIR/$step.cmd"
    if [ -f "$cmd_file" ]; then
      found=1
      printf '%s.cmd: ' "$step"
      sed -n '1p' "$cmd_file" | redact_command_line
    fi
    for suffix in out err; do
      artifact_file="$REPORT_DIR/$step.$suffix"
      if [ -f "$artifact_file" ]; then
        found=1
        printf '%s.%s: bytes=%s\n' "$step" "$suffix" "$(file_size "$artifact_file")"
      fi
    done
  done
  if [ "$found" = "0" ]; then
    printf 'none\n'
  fi
}

TITLE=${CODEXDOCK_TRENT_TITLE:-Remote E2E Report: $MACHINE $STATUS}

CONTENT=$(mktemp "${TMPDIR:-/tmp}/codexdock-trent-content.XXXXXX")
cleanup() {
  rm -f "$CONTENT"
}
trap cleanup EXIT INT TERM

{
  printf 'Remote E2E report summary\n\n'
  printf 'report_dir=%s\n' "$REPORT_DIR"
  printf 'status=%s\n' "$STATUS"
  printf 'exit_code=%s\n' "$EXIT_CODE"
  printf 'network=%s\n' "$NETWORK"
  printf 'machine=%s\n' "$MACHINE"
  printf 'session=%s\n' "$SESSION"
  printf 'session_started=%s\n' "$SESSION_STARTED"
  printf 'session_stopped=%s\n' "$SESSION_STOPPED"
  printf 'cleanup_attempted=%s\n' "$CLEANUP_ATTEMPTED"
  printf 'cleanup_exit_code=%s\n' "$CLEANUP_EXIT_CODE"
  if [ -n "$PREFLIGHT" ]; then
    printf 'preflight=%s\n' "$PREFLIGHT"
  fi
  if [ -f "$CONTEXT_FILE" ]; then
    printf '\ncontext.txt\n'
    sed -n '1,80p' "$CONTEXT_FILE"
  fi
  if [ -f "$PREFLIGHT_FILE" ]; then
    printf '\npreflight.txt\n'
    sed -n '1,80p' "$PREFLIGHT_FILE"
  fi
  printf '\ncommand artifacts\n'
  print_command_artifacts
  printf '\nresult.txt\n'
  sed -n '1,80p' "$RESULT_FILE"
} >"$CONTENT"

ENDPOINT=$BASE_URL/api/v1/data/$NAMESPACE/$OBJECT
jq -n \
  --arg name "$TITLE" \
  --arg title "$TITLE" \
  --arg artifact_type "$ARTIFACT_TYPE" \
  --arg status "$ARTIFACT_STATUS" \
  --arg project "$PROJECT" \
  --rawfile content "$CONTENT" \
  '{name:$name,values:{Title:$title,ArtifactType:$artifact_type,Status:$status,Project:$project,Content:$content}}' |
  curl -sS --fail-with-body -X POST "$ENDPOINT" \
    -H "Authorization: Bearer $TOKEN" \
    -H 'Content-Type: application/json' \
    --data-binary @-
