# Fixture change log

## 2026-01-01T00:00-baseline
type: add
target: .ai/
summary: establish fixture
reason: pin the initial cursor
affects:
by: claude

## 2026-01-01T00:01-codex-agent
type: add
target: .claude/agents/demo-developer.md
summary: add a codex-visible role
reason: exercise adapter selection
affects: codex
by: codex

## 2026-01-01T00:02-claude-command
type: update
target: .claude/commands/demo.md
summary: update the canonical command
reason: exercise the other cursor
affects: claude
by: claude

## 2026-01-01T00:03-shared-output
type: fix
target: .claude/agents/demo-reviewer.md
summary: fix a shared output contract
reason: both adapters must consume this entry
affects: claude, codex
by: codex
