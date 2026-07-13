# `.ai/` — shared cross-tool workspace

This directory is the **single source of coordination** for the two AI tools that co-develop
this repository: **Claude Code** and **OpenAI Codex CLI**. It is git-tracked, tool-neutral,
and plain markdown so any agent (or human) can read and write it without a custom parser.

Transport between tools is **git**: both tools work in the same checkout, so a commit by one
is immediately visible to the other on its next run.

## Layout

| Path | Purpose |
|------|---------|
| `memory/` | Durable knowledge about the framework — decisions, conventions, traps. Survives across sessions. `MEMORY.md` is the index. |
| `handoff.md` | The live hand-off scratchpad. Current task, status, what just landed, what's next, who picks up next, blockers. Rewritten at every session boundary. |
| `tasks/` | One markdown file per substantial work unit (e.g. the Codex action-plan brief). |
| `changes/` | The append-only agent/skill **change-log** + `sync-state.json`. Lets a sync read only *new* edits instead of re-reading the whole system. See `changes/README.md`. |
| `local/` | (git-ignored) per-machine, ephemeral scratch. Never committed. |

## Protocol (both tools follow this)

1. **Session start** — read, in order: root `AGENTS.md` (the rules) → `.ai/handoff.md`
   (where we are) → `.ai/memory/MEMORY.md` (durable knowledge) → `.ai/tasks/INDEX.md` →
   only files listed under `ACTIVE`. Do not bulk-load historical task briefs.
2. **During work** — keep the active task file's `STATUS` current; record every edit to an
   agent / skill / template as a new entry in `.ai/changes/agent-skill-log.md`.
3. **Hand-off / session end** — rewrite `.ai/handoff.md` (DONE / DECISIONS / NEXT / OWNER /
   BLOCKERS) and commit it together with your work, so `git log` is the audit trail.

This mirrors the discipline the generated pipeline already uses *between agents* (strict
structured payloads); here it runs *between tools*.
