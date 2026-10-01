#!/usr/bin/env bash
set -euo pipefail

# Build script for shellsama (Samarinda Desktop Shell) supporting FPC and tests

TARGET="${1:-fpc}"

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
    ;;
esac
