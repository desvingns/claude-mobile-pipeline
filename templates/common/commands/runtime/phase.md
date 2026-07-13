<!-- mp-runtime-mode: phase -->
<!-- mp-runtime-contracts: startup execution platform device telemetry risk-routing feature-implementation rules rules-board rules-implementation rules-fit -->

## Workflow: --phase  (assisted progression — one task per run)

Wraps the `--feature` pipeline with phase-state awareness.

### Phase 1 — Load context
Read `docs/implementation_plan/PROGRESS.md` → the row with status `active`/`in progress` → `<NN>`.
Open `phases/PHASE_<NN>_*.md`; take the first unchecked `- [ ] TASK-<NN>.k`. If none → report the
phase is complete (suggest `--check` + advancing the next phase to `active`) and stop. Re-read the
`## Anchors` the phase cites.

### Phase 2 — Synthesise SPEC (no questions — the phase file IS the spec)
Build a SPEC from the task line verbatim: `WHAT` = the task text; `LAYERS` from its controlled verb
(entity/DAO→data; repository/use-case→domain; screen/Composable/ViewModel→presentation);
`TEST_TYPES` accordingly; `CHANGED_HINT` = the phase file + cited anchors + named modules;
`CONSTRAINTS` = respect cited decisions + CLAUDE.md + `.claude/mp/extras`. Show it; ask
"SPEC ок? (y / r — edit the task line and re-run / n)".

### Phase 3 — Run pipeline
Before running the default `--feature` Phase 2, apply the **Visual autotest device pre-flight
(Android)** if the synthesized SPEC is explicitly visual and requires visual/device autotests. Run the
default `--feature` Phase 2 (Step 0 .. Step 4.5 + tests). **Skip push by default** (push per
phase, not per task): ask "Push now? (y/N — default N)".

### Phase 4 — Record progress
Tick the task `- [ ]` → `- [x]` in `PHASE_<NN>`; append to PROGRESS.md session log
`- <date>: PHASE_<NN> — <task> (commit <hash>)`. **Phase-exit hook:** if the phase now has zero
unchecked tasks, run the `--check` validator AUTOMATICALLY (read-only) and show its result, then
suggest the phase's Verification commands + setting the row to `done`. On a CLONE project
(`spec/fit/registry.csv` exists in the design source) additionally offer once:
"Phase complete — run `/{{PREFIX}} --fit` against the reference now? (y/N)" — mandatory to offer
when the completed phase was the final Fit-gate phase or touched screens.

### Phase 5 — Report
```
phase: <NN> — completed "<task>"   commit <hash>   progress <M/total> tasks
```

---
