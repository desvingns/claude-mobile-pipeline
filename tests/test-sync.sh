#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture="$repo/tests/fixtures/sync"
work="$(mktemp -d "${TMPDIR:-/tmp}/cmp-sync-test.XXXXXX")"
mkdir -p "$work/.ai/changes" "$work/.claude/agents" "$work/.claude/commands"
cp "$fixture/agent-skill-log.md" "$work/.ai/changes/agent-skill-log.md"
cp "$fixture/sync-state.json" "$work/.ai/changes/sync-state.json"
cp "$fixture/demo-developer.md" "$fixture/demo-reviewer.md" "$fixture/demo-architect.md" \
    "$work/.claude/agents/"
cp "$fixture/demo-command.md" "$work/.claude/commands/demo.md"
printf 'version: 9.9.9\nprefix: demo\n' > "$work/.claude/.cmp-version"

out="$(bash "$repo/lib/sync.sh" codex --root "$work")"
[ "$out" = '{"adapter":"codex","processed":2,"from":"2026-01-01T00:00-baseline","to":"2026-01-01T00:03-shared-output"}' ]
grep -q '^### Demo Developer$' "$work/AGENTS.md"
grep -q '^### Demo Reviewer$' "$work/AGENTS.md"
grep -q '^### Demo Architect$' "$work/AGENTS.md"
grep -q 'Output contract: BRAINSTORM.' "$work/AGENTS.md"
grep -q '^<!-- cmp-generated-adapter: codex version=9.9.9 prefix=demo -->$' "$work/AGENTS.md"
grep -q '"claude": "2026-01-01T00:00-baseline"' "$work/.ai/changes/sync-state.json"

before="$(cksum "$work/AGENTS.md")"
out="$(bash "$repo/lib/sync.sh" codex --root "$work")"
[ "$out" = '{"adapter":"codex","processed":0,"from":"2026-01-01T00:03-shared-output","to":"2026-01-01T00:03-shared-output"}' ]
[ "$before" = "$(cksum "$work/AGENTS.md")" ]

out="$(bash "$repo/lib/sync.sh" claude --root "$work")"
[ "$out" = '{"adapter":"claude","processed":2,"from":"2026-01-01T00:00-baseline","to":"2026-01-01T00:03-shared-output"}' ]
grep -q '"codex": "2026-01-01T00:03-shared-output"' "$work/.ai/changes/sync-state.json"

bad_state="$(mktemp -d "${TMPDIR:-/tmp}/cmp-sync-bad-state.XXXXXX")"
mkdir -p "$bad_state/.ai/changes" "$bad_state/.claude"
cp "$fixture/agent-skill-log.md" "$bad_state/.ai/changes/agent-skill-log.md"
printf '{"claude":false}\n' > "$bad_state/.ai/changes/sync-state.json"
if bash "$repo/lib/sync.sh" claude --root "$bad_state" >/dev/null 2>&1; then
    echo 'expected malformed state to fail' >&2
    exit 1
fi

bad_log="$(mktemp -d "${TMPDIR:-/tmp}/cmp-sync-bad-log.XXXXXX")"
mkdir -p "$bad_log/.ai/changes" "$bad_log/.claude"
cp "$fixture/sync-state.json" "$bad_log/.ai/changes/sync-state.json"
printf '## 2026-01-01T00:00-broken\ntype: add\ntarget: x\naffects: codex\nby: codex\n' \
    > "$bad_log/.ai/changes/agent-skill-log.md"
if bash "$repo/lib/sync.sh" codex --root "$bad_log" >/dev/null 2>&1; then
    echo 'expected malformed log to fail' >&2
    exit 1
fi

bad_cursor="$(mktemp -d "${TMPDIR:-/tmp}/cmp-sync-bad-cursor.XXXXXX")"
mkdir -p "$bad_cursor/.ai/changes" "$bad_cursor/.claude"
cp "$fixture/agent-skill-log.md" "$bad_cursor/.ai/changes/agent-skill-log.md"
printf '{ "claude": null, "codex": "2026-01-01T00:09-not-present" }\n' \
    > "$bad_cursor/.ai/changes/sync-state.json"
if bash "$repo/lib/sync.sh" codex --root "$bad_cursor" >/dev/null 2>&1; then
    echo 'expected a missing cursor id to fail' >&2
    exit 1
fi

no_generator="$(mktemp -d "${TMPDIR:-/tmp}/cmp-sync-no-generator.XXXXXX")"
mkdir -p "$no_generator/.ai/changes"
cp "$fixture/agent-skill-log.md" "$no_generator/.ai/changes/agent-skill-log.md"
cp "$fixture/sync-state.json" "$no_generator/.ai/changes/sync-state.json"
state_before="$(cksum "$no_generator/.ai/changes/sync-state.json")"
if bash "$repo/lib/sync.sh" codex --root "$no_generator" >/dev/null 2>&1; then
    echo 'expected missing adapter generator to fail' >&2
    exit 1
fi
[ "$state_before" = "$(cksum "$no_generator/.ai/changes/sync-state.json")" ]

# A stamped cmp project may already have a user-authored AGENTS.md. Preserve it
# before emitting the owned adapter, and mark the replacement explicitly.
protected="$(mktemp -d "${TMPDIR:-/tmp}/cmp-sync-protected.XXXXXX")"
mkdir -p "$protected/.ai/changes" "$protected/.claude/agents" "$protected/.claude/commands"
cp "$fixture/agent-skill-log.md" "$protected/.ai/changes/agent-skill-log.md"
cp "$fixture/sync-state.json" "$protected/.ai/changes/sync-state.json"
cp "$fixture/demo-developer.md" "$protected/.claude/agents/"
cp "$fixture/demo-command.md" "$protected/.claude/commands/demo.md"
printf 'version: 9.9.9\nprefix: demo\n' > "$protected/.claude/.cmp-version"
printf '# Hand-authored instructions\n' > "$protected/AGENTS.md"
bash "$repo/lib/sync.sh" codex --root "$protected" >/dev/null 2>/dev/null
grep -q '^<!-- cmp-generated-adapter: codex version=9.9.9 prefix=demo -->$' "$protected/AGENTS.md"
grep -R -q '^# Hand-authored instructions$' "$protected/.ai/archive/adapters"

# Without the cmp ownership stamp, sync must not replace a root AGENTS.md.
unstamped="$(mktemp -d "${TMPDIR:-/tmp}/cmp-sync-unstamped.XXXXXX")"
mkdir -p "$unstamped/.ai/changes" "$unstamped/.claude/agents" "$unstamped/.claude/commands"
cp "$fixture/agent-skill-log.md" "$unstamped/.ai/changes/agent-skill-log.md"
cp "$fixture/sync-state.json" "$unstamped/.ai/changes/sync-state.json"
cp "$fixture/demo-developer.md" "$unstamped/.claude/agents/"
cp "$fixture/demo-command.md" "$unstamped/.claude/commands/demo.md"
printf '# Must survive\n' > "$unstamped/AGENTS.md"
if bash "$repo/lib/sync.sh" codex --root "$unstamped" >/dev/null 2>&1; then
    echo 'expected missing cmp ownership stamp to fail' >&2
    exit 1
fi
grep -q '^# Must survive$' "$unstamped/AGENTS.md"

printf 'test-sync: ok (%s)\n' "$work"
