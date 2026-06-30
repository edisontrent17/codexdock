#!/usr/bin/env sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

VERSION=${VERSION:-dev}
COMMIT=${COMMIT:-unknown}
BUILD_DATE=${BUILD_DATE:-unknown}
DIST=${DIST:-"$ROOT/dist"}
TARGETS=${TARGETS:-"darwin/amd64 darwin/arm64 linux/amd64 linux/arm64"}
SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-0}

mkdir -p "$DIST"

write_sha256() {
  file=$1
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file"
    return
  fi
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file"
    return
  fi
  echo "sha256sum or shasum is required to write checksums" >&2
  exit 1
}

normalize_package_tree() {
  dir=$1
  if command -v touch >/dev/null 2>&1; then
    find "$dir" -exec touch -h -t 197001010000.00 {} + 2>/dev/null || find "$dir" -exec touch -t 197001010000.00 {} +
  fi
}

write_archive() {
  archive=$1
  entry=$2
  if tar --version 2>/dev/null | grep -qi 'gnu tar'; then
    tar --sort=name \
      --mtime="@$SOURCE_DATE_EPOCH" \
      --owner=0 \
      --group=0 \
      --numeric-owner \
      -czf "$archive" "$entry"
    return
  fi
  tar -czf "$archive" "$entry"
}

for target in $TARGETS; do
  target_os=${target%/*}
  target_arch=${target#*/}
  name="codexdock_${VERSION}_${target_os}_${target_arch}"
  outdir="$DIST/$name"
  binary="$outdir/codexdock"

  rm -rf "$outdir"
  mkdir -p "$outdir"

  VERSION="$VERSION" COMMIT="$COMMIT" BUILD_DATE="$BUILD_DATE" GOOS="$target_os" GOARCH="$target_arch" OUT="$binary" "$ROOT/scripts/build.sh"
  cp "$ROOT/README.md" "$ROOT/LICENSE" "$ROOT/NOTICE" "$ROOT/THIRD_PARTY_NOTICES.md" "$outdir/"
  normalize_package_tree "$outdir"

  (cd "$DIST" && write_archive "$name.tar.gz" "$name")
  (cd "$DIST" && write_sha256 "$name.tar.gz" > "$name.tar.gz.sha256")
  printf 'packaged %s\n' "$DIST/$name.tar.gz"
  printf 'checksum %s\n' "$DIST/$name.tar.gz.sha256"
done
