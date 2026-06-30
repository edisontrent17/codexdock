#!/usr/bin/env sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

usage() {
  cat <<EOF
Usage: CODEXDOCK_TRENT_TOKEN=<token> CODEXDOCK_TRENT_PROJECT=<project-id> $0 <successful-e2e-report-dir>

Environment:
  CODEXDOCK_TRENT_TOKEN        TrentPlatform bearer token
  CODEXDOCK_TRENT_TOKEN_FILE   JSON file containing personalAccessToken or accessToken
  CODEXDOCK_TRENT_PROJECT      TrentPlatform CodexDock.Project record id
  CODEXDOCK_TRENT_BASE_URL     TrentPlatform base URL (default: https://trentplatform.trentsoftware.in)
  CODEXDOCK_TRENT_NAMESPACE    Metadata namespace (default: CodexDock)
  CODEXDOCK_TRENT_ROADMAP_IDS  Roadmap item ids to close
                                (default: 111768 111769 111770 111771)
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

"$ROOT/scripts/validate-e2e-report.sh" --full "$REPORT_DIR" >/dev/null
printf 'validated remote E2E report\n'

"$ROOT/scripts/trent-record-e2e.sh" "$REPORT_DIR"
printf '\nrecorded remote E2E report in TrentPlatform\n'

"$ROOT/scripts/trent-close-roadmap.sh" "$REPORT_DIR"
