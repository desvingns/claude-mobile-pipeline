# Handoff

UPDATED: 2026-08-14 by claude

## DONE

- Analyzed a post-run report on the MyMoney SPEC `support-rewarded-ads-04-ad-reward-state`
  (~2h48m wall clock, ended green at 2131 passed / 0 failed) and traced its cost to four
  mechanical defects in this repo rather than to model or build-system behaviour. Released the
  fixes as `1.14.0` across canonical templates, both generated plugin trees, and manifests.
- **Reviewer was a no-op on multi-module projects.** `{{PREFIX}}-reviewer-android.sh` gated every
  check on `app/src/main/java/<pkg>`; MyMoney's code lives in `core/*` and `feature/*`, so it
  always answered `{"pass":true,"violations":[]}`. Layers now resolve per file; test hygiene
  covers every source set; new Check 7 catches layering inversion, declared cycles, and imports
  from an undeclared module. Added `--warn-only` and `"reviewerMode"` for adoption.
- **Risk router under-routed the SPEC.** Verified by replaying the router against the SPEC as it
  stood at routing time: `score=4, developer_tier=standard, independent_critic=false`, and the one
  signal it matched came from the substring `Token` inside `accessToken()`. Keyword lists were
  English-only, globs lowercase. Router now reads a declared `Risk-signals:` front-matter line,
  matches non-English prose, counts each signal once, and detects DI/persistence from file content.
  Same SPEC now routes `high / powerful / critic=true`.
- **The pipeline's own rule caused the six test failures.** The blanket `runBlocking` ban put real
  MockWebServer calls under `runTest`'s virtual clock. `runTest` stays the default; real-I/O tests
  opt out per call site with `// {{PREFIX}}-real-io: <reason>`.
- **No repair-loop contract existed.** Added one: stable finding IDs, a single batched holistic
  re-audit, a `resolved_findings` payload, a two-cycle budget, escalation to a new architect
  `PREFLIGHT` capsule mode, and a ratchet that raises the route when the semantic reviewer reports
  high risk or a blocker.
- Added a scoped runner mode (`--scope`), an epic-level `## Design capsule` written by the planner
  and injected into every backlog SPEC, and telemetry-compliance enforcement plus a retro
  instrumentation report.
- Rewrote the reviewer's hot path without subshells and collapsed test hygiene into one `awk`
  pass — 60 files went from 58s to 6s.

## DECISIONS

- Fixes land in canonical `templates/` (user's call), not project-local extras: the defects are
  generic to any multi-module Android project and any non-English SPEC, and text rules in
  `.claude/mp/extras/` cannot repair a bash script.
- The reviewer rolls out **warn-only first**. An audit over all 881 MyMoney sources reports 212
  findings in 69 files (design-tokens 80, layer-boundary 66, test-clock 37, test-hygiene 19,
  screen-contract 10). Switching to `enforce` is a separate, human-gated decision.
- The architecture preflight lives at **epic level** in `<epic>-00-overview.md`, written by the
  planner that already holds the design source — zero extra agent calls. The per-SPEC architect
  `PREFLIGHT` mode exists only as the escalation target when two repair cycles fail.
- Declared `Risk-signals:` is the router's primary input; prose keywords are a fallback. Signals
  are counted once each so the route reflects the kinds of risk present, not the diff size.
- Security/entitlement work that also touches state, wiring, or persistence takes the strong route
  regardless of score — that risk does not scale with diff size.

## VERIFIED

- All 11 test entry points pass, including a new `tests/test-reviewer-android.sh` that pins the
  multi-module behaviour, Check 7, the real-I/O marker, and single-module back-compat.
- `bash -n` clean on every touched and template script.
- Router replay: the case SPEC pre-implementation now returns
  `risk=high, developer_tier=powerful, independent_critic=true` (was `standard/standard/false`).
- Reviewer replay on the case's changed files now returns 18 `test-clock` findings (was
  `{"pass":true,"violations":[]}`); the two 6b false positives are gone after the window fix.
- Two false positives found by the MyMoney audit were fixed before release: foundation modules
  (`common`/`util`/`model`/`kernel`/`shared`) now rank below domain, and test-only gradle
  configurations no longer count as production dependency edges.
- Bootstrap smoke: 21 agents, 30 runtime files, 11 scripts, zero `{{...}}` / `platform:` / `tool:`
  leaks. Marketplace rebuild is idempotent; all manifests agree on `1.14.0`.
- Retro instrumentation report replayed against the real case telemetry: 100% of events missing
  `duration_ms`, correctly flagged as under-instrumented.

## NEXT

- Field validation: run the treatment on `support-rewarded-ads-05-support-ads-block-ui` and
  `-06-ads-privacy-and-app-ads-txt` (same epic, already in MyMoney's backlog). Baseline is the
  10 telemetry rows of SPEC 04. Watch semantic cycles per SPEC (was 4), full runner runs (was 2),
  `developer_tier` distribution, and the share of events carrying `duration_ms`.
- Decide when MyMoney flips `reviewerMode` from `warn-only` to `enforce`, using the 212-finding
  audit to scope the cleanup first.
- Older epics have no `## Design capsule`; backlog mode notes this and continues. Backfill only if
  an epic is still being implemented.
- Publish the release and reinstall the marketplace downstream — MyMoney currently runs the
  cached `1.12.0` plugin, so none of this reaches it until then.

## OWNER

Implementation is complete on `improve/pipeline-gates-post-rewarded-ads-04`. The user owns the
merge, the publication/reinstall, and the `warn-only → enforce` decision.
