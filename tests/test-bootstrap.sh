#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/cmp-bootstrap-test.XXXXXX")"

out="$({
  cd "$work"
  bash "$repo/bootstrap.sh" --platform=android --prefix=ft --project-name=Fixture \
    --package=com.example.fixture --skip-memory --non-interactive --no-git --dry-run
} 2>&1)"

printf '%s' "$out" | grep -q 'DRY RUN'
if printf '%s' "$out" | grep -q 'current directory is not a git repo'; then
  echo '--no-git did not suppress the documented warning' >&2
  exit 1
fi

printf 'test-bootstrap: ok (%s)\n' "$work"
