#!/usr/bin/env bash
# Preflight gate for team-code-review: build + test must pass before review starts.
# Usage: ./preflight.sh [config]   default config: Debug
# Exit 0 = pass, exit 1 = fail (prints which step failed)

set -euo pipefail

CONFIG="${1:-Debug}"
REPO_ROOT="$(git rev-parse --show-toplevel)"

echo "==> preflight: dotnet build -c $CONFIG"
if ! dotnet build "$REPO_ROOT" -c "$CONFIG" --nologo -v quiet; then
  echo "PREFLIGHT FAILED: build error. Fix before reviewing." >&2
  exit 1
fi

echo "==> preflight: dotnet test -c $CONFIG"
if ! dotnet test "$REPO_ROOT" -c "$CONFIG" --nologo --no-build -v quiet; then
  echo "PREFLIGHT FAILED: test failures. Fix before reviewing." >&2
  exit 1
fi

echo "==> preflight: PASSED"
