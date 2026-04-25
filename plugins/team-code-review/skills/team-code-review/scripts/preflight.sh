#!/usr/bin/env bash
# Preflight gate for team-code-review: build must pass before review starts.
# Usage: ./preflight.sh <stack> [config]
#   stack  — "dotnet" or "node"
#   config — Debug|Release (dotnet only, default: Debug)
# Exit 0 = pass, exit 1 = fail

set -euo pipefail

STACK="${1:-dotnet}"
CONFIG="${2:-Debug}"
REPO_ROOT="$(git rev-parse --show-toplevel)"

if [ "$STACK" = "dotnet" ]; then
  echo "==> preflight: dotnet build -c $CONFIG"
  if ! dotnet build "$REPO_ROOT" -c "$CONFIG" --nologo -v quiet; then
    echo "PREFLIGHT FAILED: build error. Fix before reviewing." >&2
    exit 1
  fi

elif [ "$STACK" = "node" ]; then
  if [ -f "$REPO_ROOT/yarn.lock" ]; then PKG="yarn"
  elif [ -f "$REPO_ROOT/pnpm-lock.yaml" ]; then PKG="pnpm"
  else PKG="npm"
  fi

  # Install deps if node_modules missing
  if [ ! -d "$REPO_ROOT/node_modules" ]; then
    echo "==> preflight: $PKG install"
    $PKG --prefix "$REPO_ROOT" install --frozen-lockfile 2>/dev/null \
      || $PKG --cwd "$REPO_ROOT" install --frozen-lockfile 2>/dev/null \
      || (cd "$REPO_ROOT" && $PKG install)
  fi

  echo "==> preflight: $PKG run build"
  if ! (cd "$REPO_ROOT" && $PKG run build); then
    echo "PREFLIGHT FAILED: build error. Fix before reviewing." >&2
    exit 1
  fi

  # TypeScript type-check (tsc --noEmit) if tsconfig present and no build script covers it
  if [ -f "$REPO_ROOT/tsconfig.json" ]; then
    if ! grep -q '"build"' "$REPO_ROOT/package.json" 2>/dev/null; then
      echo "==> preflight: tsc --noEmit"
      if ! (cd "$REPO_ROOT" && npx tsc --noEmit); then
        echo "PREFLIGHT FAILED: TypeScript type errors. Fix before reviewing." >&2
        exit 1
      fi
    fi
  fi

else
  echo "==> preflight: unknown stack '$STACK' — skipping build check (run manually)"
fi

echo "==> preflight: PASSED"
