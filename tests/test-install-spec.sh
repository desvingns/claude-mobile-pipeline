#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

claude_home="$(mktemp -d "${TMPDIR:-/tmp}/cmp-install-claude.XXXXXX")"
mkdir -p "$claude_home/.claude/skills/app-spec-creator/prompts" \
  "$claude_home/.claude/skills/app-spec-creator/scripts" "$claude_home/.claude/agents"
printf 'custom prompt\n' > "$claude_home/.claude/skills/app-spec-creator/prompts/custom.txt"
printf 'custom script\n' > "$claude_home/.claude/skills/app-spec-creator/scripts/custom.sh"
printf 'custom agent\n' > "$claude_home/.claude/agents/requirements-author.md"

if bash "$repo/install-spec.sh" --harness claude --home "$claude_home" >/dev/null 2>&1; then
  echo 'expected installer to guard an existing Claude install' >&2
  exit 1
fi
grep -q '^custom prompt$' "$claude_home/.claude/skills/app-spec-creator/prompts/custom.txt"
grep -q '^custom agent$' "$claude_home/.claude/agents/requirements-author.md"

bash "$repo/install-spec.sh" --harness claude --home "$claude_home" --force >/dev/null
[ -f "$claude_home/.claude/skills/app-spec-creator/SKILL.md" ]
archived_prompt="$(find "$claude_home/.claude/archive/app-spec-creator" \
  -path '*/skills/app-spec-creator/prompts/custom.txt' -type f -print -quit)"
archived_script="$(find "$claude_home/.claude/archive/app-spec-creator" \
  -path '*/skills/app-spec-creator/scripts/custom.sh' -type f -print -quit)"
archived_agent="$(find "$claude_home/.claude/archive/app-spec-creator" \
  -path '*/agents/requirements-author.md' -type f -print -quit)"
[ -n "$archived_prompt" ] && [ -n "$archived_script" ] && [ -n "$archived_agent" ]
grep -q '^custom prompt$' "$archived_prompt"
grep -q '^custom script$' "$archived_script"
grep -q '^custom agent$' "$archived_agent"

# Agent collisions are protected even when the skill directory itself does not
# exist. Codex owns both the canonical markdown and its TOML shim.
codex_home="$(mktemp -d "${TMPDIR:-/tmp}/cmp-install-codex.XXXXXX")"
mkdir -p "$codex_home/.codex/agents"
printf 'custom markdown\n' > "$codex_home/.codex/agents/requirements-author.md"
printf 'custom toml\n' > "$codex_home/.codex/agents/requirements-author.toml"
if bash "$repo/install-spec.sh" --harness codex --home "$codex_home" >/dev/null 2>&1; then
  echo 'expected installer to guard existing Codex agents' >&2
  exit 1
fi
grep -q '^custom markdown$' "$codex_home/.codex/agents/requirements-author.md"
grep -q '^custom toml$' "$codex_home/.codex/agents/requirements-author.toml"

bash "$repo/install-spec.sh" --harness codex --home "$codex_home" --force >/dev/null
[ -f "$codex_home/.codex/skills/app-spec-creator/SKILL.md" ]
[ -f "$codex_home/.codex/agents/requirements-author.toml" ]
codex_md="$(find "$codex_home/.codex/archive/app-spec-creator" \
  -path '*/agents/requirements-author.md' -type f -print -quit)"
codex_toml="$(find "$codex_home/.codex/archive/app-spec-creator" \
  -path '*/agents/requirements-author.toml' -type f -print -quit)"
[ -n "$codex_md" ] && [ -n "$codex_toml" ]
grep -q '^custom markdown$' "$codex_md"
grep -q '^custom toml$' "$codex_toml"

printf 'test-install-spec: ok (claude=%s, codex=%s)\n' "$claude_home" "$codex_home"
