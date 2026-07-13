<!-- mp-runtime-mode: spec -->
<!-- mp-runtime-contracts: startup backlog rules rules-board -->

## Workflow: --spec

Spec-authoring only — **fills the backlog, writes no code, runs no agents.** Use it to groom a large feature into ready-to-run SPECs ahead of time.

### Phase 1 — Draft
Explore the relevant codebase area, then run the **same grill-first elicitation as `--feature` Phase 1** (ambiguity-scaled decision tree, no fixed question cap, one decision at a time with a recommended answer). Since `--spec` is backlog grooming with no approval gate at write time, lean toward your recommended defaults and grill only the genuinely blocking forks (strategy / scope) — log the rest as `(assumption)`. Then decide single vs. split:
- **Single SPEC** → one self-contained `=== SPEC === … === END SPEC ===` block.
- **Large feature** → the full ordered set (SPEC 1..N), each its own block, + an epic overview.

### Phase 2 — Write to backlog (no approval gate)
Write the SPEC(s) **straight** to `.claude/specs/backlog/` with `Status: draft` — do NOT stop for a "SPEC ok? (y/n)" gate (approval happens at implement time, in `--feature`). Use the file format in `.claude/specs/README.md`:
- Single → `backlog/<slug>.md`.
- Split → `backlog/<epic-slug>-NN-<short>.md` (NN = order) + `backlog/<epic-slug>-00-overview.md` (goal, ordered list, dependencies, cross-cutting notes).

`Status: draft` marks an auto-written, not-yet-human-reviewed SPEC. Refine by editing the files by hand, or just implement them later — `/mp --feature --next` (or `--backlog <slug>`) runs them without re-creating or re-approving.

### Phase 3 — Report
```
spec: [topic restated]
   Wrote: N SPEC file(s) → .claude/specs/backlog/ (Status: draft)
   Files: [list]
   Next: /mp --feature --next   (or --backlog <slug>) to implement
```

---
