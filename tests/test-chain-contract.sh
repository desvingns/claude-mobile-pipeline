#!/usr/bin/env bash
# Regression checks for the Codex-only backlog conveyor contract.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROUTER="$ROOT/templates/common/commands/{{PREFIX}}.md"
FEATURE="$ROOT/templates/common/commands/runtime/feature.md"
POST_SHIP="$ROOT/templates/common/commands/runtime/contract-post-ship.md"
CODEX_SKILL="$ROOT/templates/dev/codex/skills/mp-dev/SKILL.md"
CODEX_RUNTIME="$ROOT/codex-plugins/mp-dev/skills/mp-dev/references/runtime"
CLAUDE_RUNTIME="$ROOT/claude-plugins/mp-dev/commands/mp-runtime"

grep -Fq -- '--next`, `--chain`, and `--backlog`' "$ROUTER"
grep -Fq -- '--next --chain' "$ROUTER"
grep -Fq -- '`--feature --next --chain`' "$FEATURE"
grep -Fq -- 'only when at least one runnable SPEC remains' "$POST_SHIP"
grep -Fq -- 'git branch --show-current` returns `main`' "$POST_SHIP"
grep -Fq -- 'create_thread' "$POST_SHIP"
grep -Fq -- 'environment: { type: "local" }' "$POST_SHIP"
grep -Fq -- 'empty conversation' "$POST_SHIP"
if grep -Fq -- 'fork_thread' "$POST_SHIP"; then
  echo 'chain-contract: Codex runtime must create a fresh task, not fork history' >&2
  exit 1
fi
grep -Fq -- 'send that task exactly this user-visible prompt' "$POST_SHIP"
grep -Fq -- '$mp --feature --next --chain' "$CODEX_SKILL"

bash "$ROOT/lib/build-marketplace.sh" --check-runtime >/dev/null

grep -Fq -- 'create_thread' "$CODEX_RUNTIME/contract-post-ship.md"
grep -Fq -- 'environment: { type: "local" }' "$CODEX_RUNTIME/contract-post-ship.md"
grep -Fq -- 'empty conversation' "$CODEX_RUNTIME/contract-post-ship.md"
if grep -Fq -- 'fork_thread' "$CODEX_RUNTIME/contract-post-ship.md"; then
  echo 'chain-contract: Codex thread fork API leaked into runtime' >&2
  exit 1
fi
grep -Fq -- '$mp --feature --next --chain' "$CODEX_RUNTIME/contract-post-ship.md"
if grep -Fq -- 'fork_thread' "$CLAUDE_RUNTIME/contract-post-ship.md"; then
  echo 'chain-contract: Codex thread API leaked into Claude runtime' >&2
  exit 1
fi
if grep -R -Eq '<!-- /?tool:' "$CODEX_RUNTIME" "$CLAUDE_RUNTIME"; then
  echo 'chain-contract: tool marker leaked into generated runtime' >&2
  exit 1
fi

printf '%s\n' 'chain-contract: pass'
