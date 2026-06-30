#!/usr/bin/env sh
set -eu

usage() {
  cat <<EOF
Usage: CODEXDOCK_TRENT_TOKEN=<token> $0

Environment:
  CODEXDOCK_TRENT_TOKEN        TrentPlatform bearer token
  CODEXDOCK_TRENT_TOKEN_FILE   JSON file containing personalAccessToken or accessToken
  CODEXDOCK_TRENT_BASE_URL     TrentPlatform base URL (default: https://trentplatform.trentsoftware.in)
  CODEXDOCK_TRENT_NAMESPACE    Metadata namespace (default: CodexDock)
  CODEXDOCK_TRENT_PROJECT_NAME Project record title (default: CodexDock)
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
  echo "jq is required to build TrentPlatform bootstrap payloads" >&2
  exit 2
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "curl is required to bootstrap TrentPlatform metadata" >&2
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

BASE_URL=${CODEXDOCK_TRENT_BASE_URL:-https://trentplatform.trentsoftware.in}
NAMESPACE=${CODEXDOCK_TRENT_NAMESPACE:-CodexDock}
PROJECT_NAME=${CODEXDOCK_TRENT_PROJECT_NAME:-CodexDock}

post_json() {
  path=$1
  curl -sS --fail-with-body -X POST "$BASE_URL$path" \
    -H "Authorization: Bearer $TOKEN" \
    -H 'Content-Type: application/json' \
    --data-binary @-
}

response_id() {
  label=$1
  response=$2
  id=$(printf '%s' "$response" | jq -r '.id // empty')
  if [ -z "$id" ]; then
    echo "TrentPlatform response for $label did not include an id" >&2
    exit 1
  fi
  printf '%s' "$id"
}

create_namespace() {
  jq -n \
    --arg name "$NAMESPACE" \
    --arg label "$NAMESPACE" \
    '{name:$name,label:$label,kind:"custom"}' |
    post_json "/api/v1/metadata/namespaces" >/dev/null
}

create_object() {
  name=$1
  label=$2
  plural=$3
  description=$4
  jq -n \
    --arg name "$name" \
    --arg label "$label" \
    --arg pluralLabel "$plural" \
    --arg description "$description" \
    '{name:$name,label:$label,pluralLabel:$pluralLabel,kind:"custom",description:$description}' |
    post_json "/api/v1/metadata/namespaces/$NAMESPACE/objects" >/dev/null
}

create_field() {
  object=$1
  name=$2
  label=$3
  field_type=$4
  required=$5
  reference_object=${6:-}
  if [ "$required" = "true" ]; then
    required_json=true
  else
    required_json=false
  fi
  if [ -n "$reference_object" ]; then
    jq -n \
      --arg name "$name" \
      --arg label "$label" \
      --arg fieldType "$field_type" \
      --arg referenceObject "$reference_object" \
      --arg relationshipName "${object}${name}" \
      --argjson required "$required_json" \
      '{name:$name,label:$label,fieldType:$fieldType,required:$required,referenceObject:$referenceObject,relationshipName:$relationshipName,relationshipDeleteBehavior:"restrict"}' |
      post_json "/api/v1/metadata/namespaces/$NAMESPACE/objects/$object/fields" >/dev/null
    return
  fi
  jq -n \
    --arg name "$name" \
    --arg label "$label" \
    --arg fieldType "$field_type" \
    --argjson required "$required_json" \
    '{name:$name,label:$label,fieldType:$fieldType,required:$required}' |
    post_json "/api/v1/metadata/namespaces/$NAMESPACE/objects/$object/fields" >/dev/null
}

create_project_record() {
  response=$(jq -n \
    --arg title "$PROJECT_NAME" \
    '{name:$title,values:{Title:$title,Status:"active",Scope:"CodexDock roadmap and implementation system of record."}}' |
    post_json "/api/v1/data/$NAMESPACE/Project")
  response_id "project record" "$response"
}

create_roadmap_record() {
  title=$1
  status=$2
  sort_order=$3
  jq -n \
    --arg title "$title" \
    --arg status "$status" \
    --arg sortOrder "$sort_order" \
    '{name:$title,values:{Title:$title,Status:$status,SortOrder:$sortOrder}}' |
    post_json "/api/v1/data/$NAMESPACE/RoadmapItem"
}

create_roadmap_id() {
  title=$1
  status=$2
  sort_order=$3
  response=$(create_roadmap_record "$title" "$status" "$sort_order")
  response_id "roadmap record $title" "$response"
}

append_id() {
  existing=$1
  id=$2
  if [ -z "$existing" ]; then
    printf '%s' "$id"
  else
    printf '%s %s' "$existing" "$id"
  fi
}

create_namespace

create_object Project Project Projects "CodexDock project scope."
create_field Project Title Title text true
create_field Project Status Status picklist true
create_field Project Scope Scope long_text false

create_object Artifact Artifact Artifacts "CodexDock project evidence and implementation artifacts."
create_field Artifact Title Title text true
create_field Artifact ArtifactType "Artifact Type" picklist true
create_field Artifact Status Status picklist true
create_field Artifact Project Project reference false "$NAMESPACE.Project"
create_field Artifact Content Content long_text false

create_object RoadmapItem "Roadmap Item" "Roadmap Items" "CodexDock implementation roadmap item."
create_field RoadmapItem Title Title text true
create_field RoadmapItem Status Status picklist true
create_field RoadmapItem Project Project reference false "$NAMESPACE.Project"
create_field RoadmapItem Scope Scope long_text false
create_field RoadmapItem SortOrder "Sort Order" number false

PROJECT_ID=$(create_project_record)
ROADMAP_IDS=
ROADMAP_IDS=$(append_id "$ROADMAP_IDS" "$(create_roadmap_id "Product model and command UX" done 1)")
ROADMAP_IDS=$(append_id "$ROADMAP_IDS" "$(create_roadmap_id "TrentPlatform project system of record" active 2)")
ROADMAP_IDS=$(append_id "$ROADMAP_IDS" "$(create_roadmap_id "CLI skeleton, local config, and first-time init" done 3)")
ROADMAP_IDS=$(append_id "$ROADMAP_IDS" "$(create_roadmap_id "Managed OSS component integration" active 4)")
ROADMAP_IDS=$(append_id "$ROADMAP_IDS" "$(create_roadmap_id "Machine registration and discovery" active 5)")
ROADMAP_IDS=$(append_id "$ROADMAP_IDS" "$(create_roadmap_id "SSH connect workflow" active 6)")
ROADMAP_IDS=$(append_id "$ROADMAP_IDS" "$(create_roadmap_id "Codex tmux workflow" active 7)")
ROADMAP_IDS=$(append_id "$ROADMAP_IDS" "$(create_roadmap_id "Hardening, packaging, and smoke checks" active 8)")
ROADMAP_IDS=$(append_id "$ROADMAP_IDS" "$(create_roadmap_id "Physical Mac-to-WSL E2E validation" pending 9)")

printf 'bootstrapped TrentPlatform CodexDock metadata\n'
printf 'CODEXDOCK_TRENT_PROJECT=%s\n' "$PROJECT_ID"
printf "CODEXDOCK_TRENT_ROADMAP_IDS='%s'\n" "$ROADMAP_IDS"
