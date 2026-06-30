#!/usr/bin/env sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

usage() {
  cat <<EOF
Usage: CODEXDOCK_TRENT_TOKEN=<token> CODEXDOCK_TRENT_PROJECT=<project-id> $0 <successful-e2e-report-dir>

Environment:
  CODEXDOCK_TRENT_TOKEN        TrentPlatform bearer token
  CODEXDOCK_TRENT_TOKEN_FILE   JSON file containing personalAccessToken or accessToken
  CODEXDOCK_TRENT_ENV_FILE     Sourceable env file with TrentPlatform project and roadmap ids
                                (default: $ROOT/.dev-logs/trent-codexdock.env)
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

load_trent_env_file() {
  env_file=${CODEXDOCK_TRENT_ENV_FILE:-"$ROOT/.dev-logs/trent-codexdock.env"}
  project_was_set=${CODEXDOCK_TRENT_PROJECT+x}
  project_value=${CODEXDOCK_TRENT_PROJECT-}
  repository_artifact_was_set=${CODEXDOCK_TRENT_REPOSITORY_ARTIFACT+x}
  repository_artifact_value=${CODEXDOCK_TRENT_REPOSITORY_ARTIFACT-}
  roadmap_ids_was_set=${CODEXDOCK_TRENT_ROADMAP_IDS+x}
  roadmap_ids_value=${CODEXDOCK_TRENT_ROADMAP_IDS-}
  if [ -f "$env_file" ]; then
    set -a
    . "$env_file"
    set +a
  fi
  if [ "$project_was_set" = x ]; then
    CODEXDOCK_TRENT_PROJECT=$project_value
    export CODEXDOCK_TRENT_PROJECT
  fi
  if [ "$repository_artifact_was_set" = x ]; then
    CODEXDOCK_TRENT_REPOSITORY_ARTIFACT=$repository_artifact_value
    export CODEXDOCK_TRENT_REPOSITORY_ARTIFACT
  fi
  if [ "$roadmap_ids_was_set" = x ]; then
    CODEXDOCK_TRENT_ROADMAP_IDS=$roadmap_ids_value
    export CODEXDOCK_TRENT_ROADMAP_IDS
  fi
}

load_trent_env_file

"$ROOT/scripts/validate-e2e-report.sh" --full "$REPORT_DIR" >/dev/null
printf 'validated remote E2E report\n'

"$ROOT/scripts/trent-record-e2e.sh" "$REPORT_DIR"
printf '\nrecorded remote E2E report in TrentPlatform\n'

"$ROOT/scripts/trent-close-roadmap.sh" "$REPORT_DIR"
