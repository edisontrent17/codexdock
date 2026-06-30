#!/usr/bin/env sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

VERSION=${VERSION:-dev}
COMMIT=${COMMIT:-unknown}
BUILD_DATE=${BUILD_DATE:-unknown}
TARGET_OS=${GOOS:-$(go env GOOS)}
TARGET_ARCH=${GOARCH:-$(go env GOARCH)}
OUT=${OUT:-"$ROOT/dist/codexdock"}

mkdir -p "$(dirname "$OUT")"

env CGO_ENABLED=0 GOOS="$TARGET_OS" GOARCH="$TARGET_ARCH" go build \
  -trimpath \
  -buildvcs=false \
  -ldflags "-s -w -X github.com/trentsoftware/codexdock/internal/version.Version=$VERSION -X github.com/trentsoftware/codexdock/internal/version.Commit=$COMMIT -X github.com/trentsoftware/codexdock/internal/version.Date=$BUILD_DATE" \
  -o "$OUT" \
  "$ROOT/cmd/codexdock"

printf 'built %s for %s/%s\n' "$OUT" "$TARGET_OS" "$TARGET_ARCH"
