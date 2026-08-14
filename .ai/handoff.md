# Handoff

UPDATED: 2026-08-14 by codex

## DONE

- Released the system-wide optimization batch as `1.12.0` across canonical templates, generated
  Claude/Codex plugins, manifests, documentation, and change-log cursors.
- Replaced the monolithic `/mp` prompt with a 3.4 KB fixed router plus 15 lazy runbooks and 14
  contracts; bootstrap and both plugin forms package the same runtime.
- Added risk-based developer/reviewer/verifier routing, a standard developer, semantic reviewer,
  verifier-lite, compact evidence packets, and deterministic routing tests.
- Added MP Spec budget profiles, content-addressed cache, preflight, selective fan-out, targeted
  rubric reruns, and usage reporting.
- Added bounded second-brain retrieval, inbox-only candidate writes, compact deduplicated digests,
  real/estimated usage telemetry, retrospectives, proposal archive/drain, deterministic eval, and
  validated incremental adapter sync.
- Rebuilt Graphify from canonical sources only; generated plugin/archive nodes are excluded.
- Archived the prior long handoff at
  `.ai/archive/handoffs/handoff-through-2026-07-13.md` instead of discarding history.
- Reviewed PR #7 (`improve/semantic-blocker-user-impact-v8`), fixed the Windows-only CRLF
  proposal-fixture failure, passed the full CI matrix, and merged it into `main` as `a973c2e`.
- Reviewed and merged PR #8 (`improve/retro-evidence-gates-v2`) into `main` as `3b10073`.
- Started release `1.13.0`: retro reports now gate pass-rate eligibility at three runs,
  expose low-feedback eval candidates, and cluster fail/partial evidence.

## DECISIONS

- Public `/mp` and `/mp-spec` modes, flags, structured payloads, and human gates remain compatible;
  detailed context is loaded only after mode/risk selection.
- Canonical templates remain the source of truth; generated trees are reproducible and idempotent.
- The curated brain (`core/`, `domains/`, `pipelines/`, `projects/`) is read-only to pipeline agents;
  generalized lessons can only enter `brain/inbox/` for human promotion.
- Down-tiering is conservative: deterministic/mechanical work uses cheaper routes, while ambiguous,
  broad, security-sensitive, migration, and critic work retains stronger routes.
- Cross-platform proposal tests normalize copied text fixtures to LF and disable `core.autocrlf` in
  temporary repos; production proposal-drain behavior remains unchanged.

## VERIFIED

- All repository test suites pass, including render property fuzzing, sync, proposals, eval,
  self-improvement, optimization scripts, and brain-memory integration; eval is 3/3.
- All 11 test entry points pass; Bash syntax passes for 93 scripts; JSON (24), YAML (2), and
  Python AST checks pass.
- Marketplace regeneration is idempotent; manifests agree on `1.12.0`; no placeholder, platform,
  or tool-marker leaks remain.
- Bootstrap smoke output contains 21 agents, 30 runtime files, and 11 scripts with zero leaks.
- Canonical Graphify rebuild succeeds with 1,708 nodes / 1,644 edges and zero generated-plugin or
  archive source nodes. `git diff --check` passes.
- PR #7 CI passed on Ubuntu, macOS, and Windows after the fixture fix; local validation also passed
  Bash syntax, all 11 deterministic/eval entry points, marketplace dry-run, and leak checks.

## NEXT

- Optional external validation: exercise crawl Phases 2-4 and visual gates on a throwaway AVD with
  a reference APK; this host currently exposes neither `adb` nor `emulator`.
- Observe real `/mp` and `/mp-spec` telemetry before tightening model down-tier thresholds; the
  deterministic eval and low-feedback ingestion rails are ready.
- On publication, push the release and update/reinstall the marketplace in downstream projects.

## OWNER

Implementation is complete. User/release owner controls external device validation and publication.

## BLOCKERS

None. Local shellcheck is unavailable; PR #8's GitHub Linux/macOS/Windows validation passed.
