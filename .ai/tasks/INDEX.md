# Task index — compact session entry point

Read this file at session start. Open only task files listed under **ACTIVE**; historical task files
remain in this directory for auditability and are loaded on demand, never as a bulk context dump.

## ACTIVE

None.

## VALIDATION / FOLLOW-UP

- `claude-004-reference-crawler.md` — real-device Phases 2–4 validation.
- `claude-006-loop-telemetry.md` … `claude-011-clone-fidelity.md` — authored historical stages;
  their stale status text must not be treated as current truth without checking git + the latest handoff.
- `codex-001-dual-tool.md` — legacy seam contract; remaining `lib/sync.sh` work is absorbed by codex-002.

## COMPLETE / HISTORICAL

- `codex-003-github-chain-reliability.md` — repaired standard GitHub push and Codex chain hand-off.
- `codex-002-system-optimization.md` — token, quality, memory/brain, telemetry, eval, sync, graph,
  and CI optimization release (`1.12.0`).
- `claude-002-spec-integration.md`, `claude-003-marketplace.md`, `claude-005-grill-me.md`.

Last reconciled: 2026-07-13 by codex.
