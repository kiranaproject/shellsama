#!/usr/bin/env bash
set -euo pipefail

# Build script for shellsama (Samarinda Desktop Shell) supporting FPC and tests

TARGET="${1:-fpc}"

# The binary loads libft.so from $ORIGIN, so target/libft.so is what actually runs. A
# stale copy there silently keeps using old toolkit code while the source and the
# toolkit build both look correct: the symptom is a fix that appears not to work.
# Refreshing it here means the build and the runtime cannot disagree.
refresh_libft() {
  local src="../floria-toolkit/target/libft.so"
  if [ -f "$src" ]; then
    if ! cmp -s "$src" "target/libft.so"; then
      cp -f "$src" "target/libft.so"
      echo "==> Refreshed target/libft.so from floria-toolkit"
    fi
  else
    echo "==> Warning: $src not found; leaving target/libft.so as it is" >&2
  fi
}

case "${TARGET}" in
  test)
    echo "==> Running tests with FPC..."
    shift 1 || true
    pasbuild test "$@"
    ;;
  clean)
    echo "==> Cleaning target artifacts..."
    shift 1 || true
    pasbuild clean "$@"
    ;;
  fpc|*)
    echo "==> Compiling with Free Pascal Compiler (FPC)..."
    if [ "${TARGET}" = "fpc" ]; then
      shift 1 || true
    fi
    pasbuild compile "$@"
    refresh_libft
    ;;
esac
