<!-- mp-runtime-mode: plan -->
<!-- mp-runtime-contracts: startup execution backlog rules rules-board -->

## Workflow: --plan  (spec → backlog bridge)

Turns a design source into an ordered set of ready-to-run SPECs on the `.claude/specs/backlog/`
board. Use after `/mp-spec` produces a `spec/` bundle, or to break a TDD/design doc into slices.

### Phase 1 — Plan
Parse args: `<epic-slug>` (kebab-case) + optional `--from <path>` (an `/mp-spec` bundle dir or a
TDD/design file; default: ask). Spawn `mp-planner`:
```
mode: bootstrap        (or `sync` if an epic with this slug already exists in the backlog)
design_source: <path or "">
epic_slug: <slug>
```
Parse its `=== PLAN ===` block.

### Phase 2 — Gated write
Show the planned SPEC filenames + which one promotes first. Ask: "Write N SPEC files to
`.claude/specs/backlog/`? (y/d/n)" — `y` writes overview + SPECs verbatim from `rendered_markdown`;
`d` shows full bodies first; `n` aborts. On `y`, promote the `promote:true` SPEC to `active/`. Never
write outside `.claude/specs/`.

### Phase 3 — Report
```
plan: <epic-slug> — N SPEC(s) → .claude/specs/backlog/ (Status: draft)
   Next: /mp --feature --next   (implements the top-ordered SPEC)
```

---

## Workflow: --plan --phases  (design → numbered phase plan; clone/large builds)

The HEAVY planning bridge: turn a design source into `docs/implementation_plan/phases/PHASE_NN_*.md`
+ PROGRESS/00_overview deltas via `mp-phase-planner`, behind a gate. (Ad-hoc features use the
plain `--plan` → backlog board instead; the two coexist.)

### Phase 1 — Plan
Resolve `mode`: `--bootstrap` if no `phases/` yet, else `--sync`; `--phase NN` regenerates one phase.
If `docs/implementation_plan/` is absent and `--bootstrap`, first scaffold it from the plugin's
`implementation_plan/*.tmpl` (README/00_overview/PROGRESS). Spawn `mp-phase-planner` with
`{mode, design_source: "<--from path or empty>", repo_root: $(git rev-parse --show-toplevel), generated: "<today>"}`.
Parse its single `=== PLAN ===` block (retry ONCE with a "block only" preface on parse failure).

### Phase 2 — Coverage audit + preview + gate
**Plan-coverage audit (deterministic, BEFORE the gate).** When the design source is a spec
bundle, cross-check that everything in it landed in the plan:
1. Collect the design-side IDs: `spec/fit/registry.csv` → every `screen_id` (clone);
   `spec/traceability.csv` → every `fr_id` (and `us_id` where no FR); the inventory's epics.
2. Grep the emitted phases' `rendered_markdown` (all of them) for each ID: every registry
   `screen_id` must appear in ≥1 task (its Visual-QA task at minimum); every `FR-`/`US-` id must
   appear in ≥1 task's `traces`/text.
3. Print the audit: `covered: X/Y screens, M/N FRs` + the explicit list of UNCOVERED ids.
4. **Non-empty uncovered list is a blocker:** ask the user — `r` re-spawn the planner with the
   uncovered list appended to its input ("these design items are missing from the plan — place
   each or mark it deferred"), or `a` acknowledge explicitly (each acknowledged id is written
   into the 00_overview deltas as a `deferred (user-acknowledged)` row so it stays visible).
   Never write a plan with silently-missing design items.

Then print: files to create/merge, the per-file merge summary (preserved/updated/added/conflict), the
PROGRESS/00_overview deltas, and every `warnings[]` entry. Ask:
"Write/merge N phase files + PROGRESS/overview deltas? (y / d — full diff / n)".
- **d** → dump each `rendered_markdown` + a unified diff vs the on-disk file, then re-ask.
- **n** → write nothing.
- **y** → Phase 3.

### Phase 3 — Gated write (orchestrator only — the ONLY writes here)
For each phase, merge `rendered_markdown` into `phases/PHASE_NN_*.md` honouring the sentinels:
regenerate `<!-- mp:plan:gen … -->` regions ONLY; NEVER touch `## Notes for next session`;
preserve checkbox state by `TASK-NN.k`. If a human edited inside a gen region (region hash ≠ stored
`hash=`) → write the proposal to `phases/.proposed/PHASE_NN.md` and report it. Append the
`progress_delta` rows + the one decisions-log line to `PROGRESS.md` (append-only — never rewrite
prose). Apply `overview_delta` to `00_overview.md`. Write nothing else (no source, no design source).

### Phase 4 — Report
```
plan: <mode> — <N> phase files (<created>/<merged>/<conflict→.proposed>)
   Anchors: content-addressed (slug+hash); drift: <none|list>
   Next: /mp --check, then /mp --phase
```

---
