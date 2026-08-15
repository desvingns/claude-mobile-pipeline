# Handoff

Last session: Claude · 2026-08-15 · released **1.15.0** on `main`.

## DONE

Analysed the `plus-subscription-gating-05` postmortem plus raw MyMoney telemetry
(`selfimprove/runs/2026-08.jsonl`, correlations `…-05` and `…-06`) and shipped the fixes.

The 1.14.0 gates worked — `route_escalated=1`, `mode=scoped`, `repair_cycle=N`, `finding_ids`,
`rule=test-clock` and the capsule escalation all appear in the recorded events. They did not
reduce wall clock, because the deterministic gates they sped up totalled 123 seconds across the
whole SPEC. Measured breakdown of the `…-05` window (20:59:56Z → 03:50:32Z, 410 min):

| item | time | share |
|---|---|---|
| human gate after the capsule (22:43 → 03:26) | 268 min | 65% |
| semantic review, 4 recorded passes | 42 min | 10% |
| developer repairs, 2 recorded | 27 min | 7% |
| deterministic gates + runners | 6 min | 1.5% |
| unrecorded gaps inside the window | 68 min | 16% |

Sum of all `duration_ms` = 74.7 min = **18%** of the window. The commit window runs to 06:42Z,
so a further **2 h 52 min** and eight commits sit outside telemetry entirely. `tester`,
`verifier`, `architect` and `critic` emitted no events at all. On `…-06`, three documented
semantic passes produced zero `semantic-reviewer` events.

Shipped (all in canonical `templates/`, both adapters rebuilt):

- **P0-A** capsule `VERDICT` + conditional gate + `--unattended`. The 1.14.0 gate was mine and
  was the single largest cost item on the run.
- **P0-B** `{{PREFIX}}-spec-complexity.sh` + `Acceptance-matrix:` declaration + planner rule.
- **P0-C** frozen obligation matrix; semantic passes return `coverage`.
- **P0-D** per-module gradle task resolution + `error_kind:task_not_found` (my `--scope`
  regression from 1.14.0).
- **P1-A** phase telemetry, `human_wait_ms`, retro splits agent time from human wait.
- **P1-B** reviewer Check 8 `usecase-test`.
- **P1-C** tester self-check before return.
- **P2** 10-minute agent liveness policy.

## DECISIONS

- **Size is declared, not inferred.** A breadth score computed from `CHANGED_HINT` was built
  first and discarded: run against the whole epic it flagged 5 of 6 SPECs and ranked the
  6-hour one *lowest*, because that SPEC's `CHANGED_HINT` named two modules while the work
  crossed seven plus a Supabase grant. Anything derived from it is measuring a guess. The
  `Acceptance-matrix:` cross-product ranks the same six correctly (05 → 60 cells, 06 → 12).
- **Blocking is asymmetric.** An unnecessary gate costs hours; a wrong `PATCH ALLOWED` costs
  one review cycle the loop was already going to run. The architect is told this explicitly.
- The two-cycle budget no longer resets after a capsule — it becomes one final cycle, then a
  handoff. `…-06` shows the failure mode of the old rule: stopped mid-SPEC, still in `active/`.

## VERIFIED

- 13 test entry points pass, including new `tests/test-runner-android.sh` and Check 8 /
  size-gate cases. `bash -n` clean on every touched script.
- `tests/test-runner-android.sh` found a real bug while being written: the `task_not_found`
  carve-out was dead in exactly the case it exists for (zero test suites set `FAILED=1` before
  the classification ran). Fixed by classifying from the gradle log first.
- Smoke bootstrap: 21 agents, 12 scripts, zero `{{...}}` / `platform:` / `tool:` leaks.
- Marketplace rebuild byte-identical across two consecutive runs; all manifests at 1.15.0.

## NEXT (user-owned)

- **MyMoney must reinstall the plugin** — it is pinned to the 1.14.0 cache; none of this
  reaches the project until then.
- `plus-subscription-gating-06` is still half-done in `active/` with a handoff written by the
  old contract. Under 1.15.0 the third blocker-pass would have continued on `PATCH ALLOWED`
  instead of stopping.
- Backfill `Acceptance-matrix:` on the epic's remaining backlog SPECs; without it the gate
  returns `undeclared` and the orchestrator derives the line before implementing.
- The `warn-only → enforce` decision for MyMoney's reviewer is still open (212-finding audit
  from 1.14.0). Note MyMoney's config has no `reviewerMode`, so it is currently on `enforce`.

## OWNER

Claude. Codex owns `lib/render.sh`, `lib/sync.sh`, `bootstrap.sh`, `.codex/` as before —
untouched this session.

## BLOCKERS

None.
