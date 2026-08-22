#!/usr/bin/env bash
# Regression checks for credential-helper based pushes in the standard MP runtime.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PUSH_FILES=(
  "$ROOT/templates/common/commands/runtime/contract-feature-implementation.md"
  "$ROOT/templates/common/commands/runtime/bugfix.md"
  "$ROOT/templates/common/memory/git-push-via-token.md.tmpl"
)

for file in "${PUSH_FILES[@]}"; do
  grep -Fq -- 'git push origin HEAD' "$file" || {
    echo "github-push-contract: origin-first push missing in ${file#$ROOT/}" >&2
    exit 1
  }
  grep -Fq -- 'GIT_TERMINAL_PROMPT=0' "$file" || {
    echo "github-push-contract: prompt guard missing in ${file#$ROOT/}" >&2
    exit 1
  }
  grep -Fq -- 'GITHUB_TOKEN:-' "$file" || {
    echo "github-push-contract: optional-token guard missing in ${file#$ROOT/}" >&2
    exit 1
  }
done

if grep -Fq -- 'Token is provided via the GITHUB_TOKEN env var' \
    "$ROOT/templates/common/commands/runtime/contract-feature-implementation.md" \
    "$ROOT/templates/common/commands/runtime/bugfix.md" \
    "$ROOT/templates/common/commands/runtime/coverage-headings.txt"; then
  echo 'github-push-contract: runtime still treats GITHUB_TOKEN as mandatory' >&2
  exit 1
fi

bash "$ROOT/lib/build-marketplace.sh" --check-runtime >/dev/null
GENERATED_FILES=(
  "$ROOT/codex-plugins/mp-dev/skills/mp-dev/references/runtime/contract-feature-implementation.md"
  "$ROOT/codex-plugins/mp-dev/skills/mp-dev/references/runtime/bugfix.md"
  "$ROOT/claude-plugins/mp-dev/commands/mp-runtime/contract-feature-implementation.md"
  "$ROOT/claude-plugins/mp-dev/commands/mp-runtime/bugfix.md"
)
for file in "${GENERATED_FILES[@]}"; do
  grep -Fq -- 'git push origin HEAD' "$file" || {
    echo "github-push-contract: generated origin-first push missing in ${file#$ROOT/}" >&2
    exit 1
  }
done

printf '%s\n' 'github-push-contract: pass'
