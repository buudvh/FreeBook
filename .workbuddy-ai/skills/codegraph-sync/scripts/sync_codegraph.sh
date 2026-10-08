#!/usr/bin/env bash
#
# sync_codegraph.sh — ensure the CodeGraph index exists and is current.
#
# Usage:
#   sync_codegraph.sh [--full] [path]
#     path    project / repo root (default: current directory)
#     --full  rebuild the entire index from scratch (codegraph index)
#
# Exit codes:
#   0  index present & usable (or freshly built) — non-fatal warnings printed
#   2  unknown option
#   3  'codegraph' not found on PATH
#
# Note: codegraph init/sync may exit non-zero on per-file parse timeouts (large
# legacy files) while still producing a usable index. This script treats that
# as a warning, not a hard failure.

set -uo pipefail

TARGET="."
FULL=0
while [ $# -gt 0 ]; do
  case "$1" in
    --full) FULL=1 ;;
    --*) echo "Unknown option: $1" >&2; exit 2 ;;
    *) TARGET="$1" ;;
  esac
  shift
done

if ! command -v codegraph >/dev/null 2>&1; then
  echo "ERROR: 'codegraph' not found on PATH." >&2
  echo "Install it first (codegraph upgrade, or install.ps1 from the GitHub release)." >&2
  exit 3
fi

# Resolve to an absolute path so subcommands see the right project root.
TARGET="$(cd "$TARGET" 2>/dev/null && pwd)" || {
  echo "ERROR: cannot resolve path '$TARGET'." >&2
  exit 2
}

INDEX_DIR="$TARGET/.codegraph"

if [ ! -d "$INDEX_DIR" ]; then
  echo "No .codegraph/ index in $TARGET — building a fresh index (codegraph init --yes)."
  codegraph init --yes "$TARGET"
  # init may exit non-zero on parse timeouts but still build a usable index.
  echo "Fresh index built in $TARGET (verify with: codegraph status '$TARGET')."
  exit 0
fi

if [ "$FULL" -eq 1 ]; then
  echo "Rebuilding full index in $TARGET (codegraph index)."
  codegraph index "$TARGET"
  echo "Full rebuild complete in $TARGET."
  exit 0
fi

echo "Index present in $TARGET — syncing changes (codegraph sync)."
OUT="$(codegraph sync "$TARGET" 2>&1)"
RC=$?

if [ $RC -ne 0 ]; then
  if printf '%s' "$OUT" | grep -qi "lock"; then
    echo "Stale lock detected — running 'codegraph unlock' then retrying sync."
    codegraph unlock "$TARGET" >/dev/null 2>&1 || true
    codegraph sync "$TARGET"
    echo "Sync complete after unlock."
    exit 0
  fi
  echo "WARN: 'codegraph sync' exited $RC; the index may still be usable." >&2
  printf '%s\n' "$OUT" | tail -20 >&2
  echo "If queries return stale/missing symbols, re-run with --full, or check .codegraph/errors.log." >&2
  exit 0
fi

printf '%s\n' "$OUT"
echo "Sync complete in $TARGET."
