#!/usr/bin/env sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

usage() {
  cat <<EOF
Usage: CODEXDOCK_TRENT_ADMIN_EMAIL=<email> CODEXDOCK_TRENT_ADMIN_PASSWORD=<password> $0

Environment:
  CODEXDOCK_TRENT_BASE_URL             TrentPlatform base URL (default: https://trentplatform.trentsoftware.in)
  CODEXDOCK_TRENT_ORG_NAME             Org API name (default: CodexDock<utc timestamp>)
  CODEXDOCK_TRENT_ORG_LABEL            Org label (default: CodexDock)
  CODEXDOCK_TRENT_ADMIN_EMAIL          First admin email (required)
  CODEXDOCK_TRENT_ADMIN_PASSWORD       First admin password (required by TrentPlatform signup)
  CODEXDOCK_TRENT_ADMIN_DISPLAY_NAME   First admin display name (default: CodexDock Admin)
  CODEXDOCK_TRENT_TOKEN_FILE           Token JSON destination (default: /tmp/trentplatform-codexdock-admin.json)
  CODEXDOCK_TRENT_ENV_FILE             Bootstrap env destination (default: $ROOT/.dev-logs/trent-codexdock.env)
  CODEXDOCK_TRENT_NAMESPACE            Metadata namespace passed to trent-bootstrap.sh (default: CodexDock)
  CODEXDOCK_TRENT_PROJECT_NAME         Project record title passed to trent-bootstrap.sh (default: CodexDock)
EOF
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  usage
  exit 0
fi

if [ "$#" -ne 0 ]; then
  usage >&2
  exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required to provision TrentPlatform metadata" >&2
  exit 2
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "curl is required to provision TrentPlatform metadata" >&2
  exit 2
fi

BASE_URL=${CODEXDOCK_TRENT_BASE_URL:-https://trentplatform.trentsoftware.in}
ORG_NAME=${CODEXDOCK_TRENT_ORG_NAME:-CodexDock$(date -u +%Y%m%d%H%M%S)}
ORG_LABEL=${CODEXDOCK_TRENT_ORG_LABEL:-CodexDock}
ADMIN_EMAIL=${CODEXDOCK_TRENT_ADMIN_EMAIL:-}
ADMIN_PASSWORD=${CODEXDOCK_TRENT_ADMIN_PASSWORD:-}
ADMIN_DISPLAY_NAME=${CODEXDOCK_TRENT_ADMIN_DISPLAY_NAME:-CodexDock Admin}
TOKEN_FILE=${CODEXDOCK_TRENT_TOKEN_FILE:-/tmp/trentplatform-codexdock-admin.json}
ENV_FILE=${CODEXDOCK_TRENT_ENV_FILE:-"$ROOT/.dev-logs/trent-codexdock.env"}

require_not_blank() {
  name=$1
  value=$2
  case "$value" in
    *[![:space:]]*) ;;
    *)
      echo "$name is required" >&2
      exit 2
      ;;
  esac
}

require_not_blank CODEXDOCK_TRENT_ORG_NAME "$ORG_NAME"
require_not_blank CODEXDOCK_TRENT_ORG_LABEL "$ORG_LABEL"
require_not_blank CODEXDOCK_TRENT_ADMIN_EMAIL "$ADMIN_EMAIL"
require_not_blank CODEXDOCK_TRENT_ADMIN_PASSWORD "$ADMIN_PASSWORD"
require_not_blank CODEXDOCK_TRENT_ADMIN_DISPLAY_NAME "$ADMIN_DISPLAY_NAME"
require_not_blank CODEXDOCK_TRENT_TOKEN_FILE "$TOKEN_FILE"
require_not_blank CODEXDOCK_TRENT_ENV_FILE "$ENV_FILE"

org_name_length=${#ORG_NAME}
case "$ORG_NAME" in
  [ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz]*) ;;
  *)
    echo "CODEXDOCK_TRENT_ORG_NAME must start with a letter and contain only letters and numbers" >&2
    exit 2
    ;;
esac
case "$ORG_NAME" in
  *[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789]*)
    echo "CODEXDOCK_TRENT_ORG_NAME must start with a letter and contain only letters and numbers" >&2
    exit 2
    ;;
esac
if [ "$org_name_length" -lt 3 ] || [ "$org_name_length" -gt 63 ]; then
  echo "CODEXDOCK_TRENT_ORG_NAME must be 3 to 63 characters" >&2
  exit 2
fi

post_json() {
  path=$1
  shift
  curl -sS --fail-with-body -X POST "$BASE_URL$path" \
    "$@" \
    -H 'Content-Type: application/json' \
    --data-binary @-
}

response_token() {
  label=$1
  response=$2
  token=$(printf '%s' "$response" | jq -r '.personalAccessToken // .accessToken // empty')
  if [ -z "$token" ]; then
    echo "TrentPlatform response for $label did not include an access token" >&2
    exit 1
  fi
  printf '%s' "$token"
}

signup_response=$(jq -n \
  --arg orgName "$ORG_NAME" \
  --arg orgLabel "$ORG_LABEL" \
  --arg adminEmail "$ADMIN_EMAIL" \
  --arg password "$ADMIN_PASSWORD" \
  --arg displayName "$ADMIN_DISPLAY_NAME" \
  '{orgName:$orgName,orgLabel:$orgLabel,adminEmail:$adminEmail,password:$password,displayName:$displayName}' |
  post_json "/api/v1/auth/signup")
TENANT_TOKEN=$(response_token "org signup" "$signup_response")

pat_response=$(jq -n \
  '{name:"CodexDock Agent",scopes:["metadata:read","metadata:write","data:read","data:write","query:execute"]}' |
  post_json "/api/v1/auth/personal-access-tokens" -H "Authorization: Bearer $TENANT_TOKEN")
PAT_TOKEN=$(response_token "personal access token" "$pat_response")

mkdir -p "$(dirname -- "$TOKEN_FILE")"
umask 077
jq -n \
  --arg orgName "$ORG_NAME" \
  --arg adminEmail "$ADMIN_EMAIL" \
  --arg personalAccessToken "$PAT_TOKEN" \
  '{
    orgName:$orgName,
    adminEmail:$adminEmail,
    personalAccessToken:$personalAccessToken,
    scopes:["metadata:read","metadata:write","data:read","data:write","query:execute"]
  }' >"$TOKEN_FILE"
chmod 600 "$TOKEN_FILE"

CODEXDOCK_TRENT_TOKEN_FILE="$TOKEN_FILE" \
  CODEXDOCK_TRENT_ENV_FILE="$ENV_FILE" \
  CODEXDOCK_TRENT_BASE_URL="$BASE_URL" \
  "$ROOT/scripts/trent-bootstrap.sh"

printf 'provisioned TrentPlatform org %s\n' "$ORG_NAME"
printf 'wrote TrentPlatform token file: %s\n' "$TOKEN_FILE"
