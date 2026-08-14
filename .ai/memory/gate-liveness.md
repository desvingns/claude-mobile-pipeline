---
name: gate-liveness
description: a deterministic gate can be silently inert on a project's layout; assert it produces findings, never trust a clean pass
---

# Gate liveness — a green gate is not evidence a gate ran

`{{PREFIX}}-reviewer-android.sh` gated every one of its six checks on a single hard-coded source
root, `app/src/main/java/<packagePath>`. On a multi-module project — `core/*`, `feature/*`, with
sources under `src/main/kotlin` as well as `src/main/java` — nothing matched, so it skipped every
check and returned `{"pass":true,"violations":[]}` in about fifteen seconds. It reported that
result for over a year, and every consumer read it as "the change is architecturally clean".

The cost is not the missing findings. It is that the cheap gate's silence pushed all of its work
onto the expensive one: the semantic reviewer found the layer and dependency problems instead, one
cluster per round-trip, at LLM latency and LLM price.

## What this means for any deterministic gate we write

- **A pass is ambiguous.** `pass=true` means "found nothing" and "looked at nothing" identically.
  Any gate whose scope is derived from a path convention can be silently inert on a layout its
  author did not have in front of them.
- **Test against a real project layout, not the fixture the gate was written for.** The bug
  survived a full test suite because every fixture used the single-module layout the script
  assumed. `tests/test-reviewer-android.sh` now builds a synthetic multi-module tree and asserts
  the checks actually *fire* — an assertion that a violation is reported is worth more than an
  assertion that a clean file passes.
- **Prefer content over naming conventions.** The same class of bug hit the risk router: case-
  sensitive globs like `*repository*` and `*Hilt*Module*` never match real Kotlin file names
  (`SupabaseAdRewardRepository.kt`, `SharedModule.kt`), so those signals were dead. Detect Hilt from
  `@Module`/`@InstallIn` in the file, not from what someone named it.
- **Language-bound heuristics are the same failure.** The router's keyword lists were English-only,
  so a SPEC written in the team's language scored as routine work. Anything a planner already knows
  should be declared (`Risk-signals:`), with keyword matching kept as fallback.
- **When widening a check that has never run, ship `--warn-only` first.** Turning on six checks
  against an established codebase surfaced 212 findings; blocking on day one would have taught the
  team to route around the gate.

Related: [[change-log-discipline]], [[self-improvement-loop]].
