<!-- mp-runtime-mode: coverage -->
<!-- mp-runtime-contracts: startup execution platform rules -->

## Workflow: --coverage  (Android only — diagnostic, read-only)

Surfaces JaCoCo line coverage per package and proposes which classes to test next. Does not modify any files, does not push, does not block. Use it when planning the next iteration or after a debt-paydown sprint.

Skip entirely on iOS-only projects (the agent does not exist there).

### Phase 1 — Run

Parse optional arguments:
- `<scope>` (positional) — package glob to focus on (default: entire project).
- `--target=N` — line-coverage minimum, integer 0-100 (default: 65).

Spawn agent `mp-coverage-android` with prompt:
```
Report JaCoCo unit-test coverage. Return JSON per your output spec.

scope: [scope arg or "all"]
target: [target value or 65]
```

### Phase 2 — Report

Print the agent's JSON verbatim, then a short human-readable summary:

```
Coverage: [project_coverage] (target: [target])
Weak packages:
  - [package]: [coverage]  (untested: [count])
Top suggestions:
  1. [first suggestion]
  2. [second suggestion]
  3. [third suggestion]
Next: feed a suggestion into /mp --feature to write the missing tests
```

The coverage agent never writes tests itself. Hand the result back to `/mp --feature` (or `--tdd`) when you want to act on it.

---
