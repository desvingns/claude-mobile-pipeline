<!-- mp-runtime-mode: check -->
<!-- mp-runtime-contracts: startup rules rules-board -->

## Workflow: --check  (read-only validator)

Reports PROGRESS ↔ PHASE ↔ design-anchor consistency. Makes NO changes.

Checks: (1) exactly one `active`/`in progress` row in PROGRESS → `<NN>`; (2) `phases/PHASE_<NN>_*.md`
exists; (3) it has ≥1 unchecked task (else the phase is complete — warn); (4) if `<NN>` is not the
first phase, the previous one is `done` with all boxes ticked; (5) **anchor drift** — for each
`slug:+h:` anchor, if the design source is reachable recompute the section hash; mismatch → report
`§X.Y drifted — run /mp --plan --phases --sync` (a warning, not a hard fail); if the design is
off-host report Check 5 as `skipped (design off-host)`; (6) customisation layer
(`.claude/mp/config.json`, `.claude/mp/extras/`) present. Print each check ✓/✗/⚠ +
`Status: CONSISTENT | INCONSISTENT (N issues)`; if inconsistent, enumerate fixes — do NOT auto-fix.

---
