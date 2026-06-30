#!/usr/bin/env sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

usage() {
  cat <<EOF
Usage: $0 <codexdock-binary-or-tar.gz>

Environment:
  PREFIX  Installation prefix (default: \$HOME/.local)
  BINDIR  Binary destination directory (default: \$PREFIX/bin)
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

SOURCE=$1
if [ ! -f "$SOURCE" ]; then
  echo "install source not found: $SOURCE" >&2
  exit 2
fi

PREFIX=${PREFIX:-"$HOME/.local"}
BINDIR=${BINDIR:-"$PREFIX/bin"}
DEST="$BINDIR/codexdock"

verify_checksum() {
  archive=$1
  checksum=$archive.sha256
  if [ ! -f "$checksum" ]; then
    return 0
  fi
  archive_dir=$(CDPATH= cd -- "$(dirname -- "$archive")" && pwd)
  archive_name=$(basename -- "$archive")
  if command -v sha256sum >/dev/null 2>&1; then
    (cd "$archive_dir" && sha256sum -c "$archive_name.sha256" >/dev/null)
    return
  fi
  if command -v shasum >/dev/null 2>&1; then
    expected=$(sed -n '1s/[[:space:]].*//p' "$checksum")
    actual=$(shasum -a 256 "$archive" | sed -n '1s/[[:space:]].*//p')
    if [ "$expected" != "$actual" ]; then
      echo "checksum verification failed: $archive" >&2
      exit 1
    fi
    return
  fi
  echo "sha256sum or shasum is required to verify $checksum" >&2
  exit 1
}

install_binary() {
  binary=$1
  mkdir -p "$BINDIR"
  cp "$binary" "$DEST"
  chmod 755 "$DEST"
  printf 'installed %s\n' "$DEST"
}

case "$SOURCE" in
  *.tar.gz)
    verify_checksum "$SOURCE"
    TMP=${TMPDIR:-/tmp}
    WORK=$(mktemp -d "$TMP/codexdock-install.XXXXXX")
    cleanup() {
      rm -rf "$WORK"
    }
    trap cleanup EXIT INT TERM
    tar -xzf "$SOURCE" -C "$WORK"
    binary=$(find "$WORK" -type f -name codexdock -perm -u+x | sed -n '1p')
    if [ -z "$binary" ]; then
      binary=$(find "$WORK" -type f -name codexdock | sed -n '1p')
    fi
    if [ -z "$binary" ]; then
      echo "codexdock binary not found in archive: $SOURCE" >&2
      exit 1
    fi
    install_binary "$binary"
    ;;
  *)
    install_binary "$SOURCE"
    ;;
esac

case ":$PATH:" in
  *":$BINDIR:"*) ;;
  *) printf 'note: add %s to PATH to run codexdock directly\n' "$BINDIR" ;;
esac

if [ -x "$DEST" ]; then
  "$DEST" version
fi
