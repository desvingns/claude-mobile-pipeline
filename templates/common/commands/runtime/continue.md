<!-- mp-runtime-mode: continue -->
<!-- mp-runtime-contracts: startup backlog rules rules-board -->

## Workflow: --continue  (state machine — propose the next conveyor step)

The single re-entry point: the user types `/{{PREFIX}} --continue` instead of remembering the
`--plan --phases → --phase × N → --fit → --feature --next` chain. Read-only until the user
accepts the proposal.

### Phase 1 — Inspect state (read-only, in this order)
1. `.claude/specs/active/` — a SPEC mid-flight?
2. `docs/implementation_plan/PROGRESS.md` (if present) — the `active`/`in progress` phase row,
   and whether `phases/PHASE_<NN>_*.md` still has unchecked tasks; whether ALL phases are `done`.
3. `.claude/specs/backlog/` — runnable SPECs queued (ignore `*-00-overview.md`)?
4. Clone state — does `spec/fit/registry.csv` (or config `referenceScreenshotsDir`) exist, and
   did the last `--fit` (epic `fit` SPECs in backlog/done, `build/fit/` captures) leave
   unexplained divergences or has it never run since the last phase completed?
5. Secondary signals: `retro_due` from the latest telemetry call; queued proposals in
   `mp_repo/.ai/proposals/` (resolve as in `--improve`, skip silently if unresolved).

### Phase 2 — Pick ONE recommendation (first match wins)
1. Active SPEC exists → `/{{PREFIX}} --feature --next` (resume it).
2. Active phase has unchecked tasks → `/{{PREFIX}} --phase`.
3. A phase just completed (zero unchecked) but its row isn't `done` → `/{{PREFIX}} --check`,
   then advance the row.
4. All phases done + clone + fit pending/divergent → `/{{PREFIX}} --fit`.
5. Backlog non-empty → `/{{PREFIX}} --feature --next`.
6. Fit clean + backlog empty + phases done → say the conveyor is drained; suggest
   `/{{PREFIX}} --spec` / `--feature <idea>` (and surface the secondary signals).

### Phase 3 — Propose + gated run
Print: the recommended command, ONE line of why (grounded in what Phase 1 found), and any
secondary suggestions (retro due / proposals queued) as bullets — then ask
"Run it now? (y/N)". On `y` execute that workflow exactly as if the user typed it (its own
gates still apply); on `N` stop. Never run anything before the `y`.

---
