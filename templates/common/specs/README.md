# `.claude/specs/` — SPEC backlog board + brainstorm artifacts

This directory is a lightweight, **file-based task board for SPECs**, plus the home of
`/{{PREFIX}} --discuss` brainstorm records. It exists so a feature that is **too large for one
SPEC** is stored, ordered, and resumable across sessions — instead of living only in one chat.

**Committed to git** — long-term visibility into what we planned and why. A backlog SPEC that
went nowhere is still useful evidence of considered trade-offs.

## Layout

```
.claude/specs/
  README.md      # this contract
  backlog/       # SPECs queued, not started (+ an optional <epic>-00-overview.md)
  active/        # the SPEC(s) currently being implemented — normally exactly one
  done/          # shipped SPECs, with commit + changed files filled in
  <slug>.md      # (root) --discuss brainstorm artifacts
```

A SPEC's **status is the folder it lives in** (`backlog` / `active` / `done`). Moving the file
between folders is how its status changes — there is no separate state store.

## When the board is used

- `/{{PREFIX}} --feature <large feature>` — if Phase 1 finds the feature splits into **≥2
  independently-shippable SPECs**, the orchestrator writes each SPEC as a file in `backlog/`
  (behind one y/N gate), then promotes the first to `active/` and implements it. The rest wait
  in `backlog/` for the next run.
- `/{{PREFIX}} --spec <description>` — **author SPEC(s) only** and write them straight to `backlog/`
  (`Status: draft`, no approval gate). The way to fill the backlog without implementing.
- `/{{PREFIX}} --feature --next` (or `--backlog <slug>`) — **implement a SPEC already in the
  backlog**: it is treated as already created + approved, so Phase 0/1 are skipped — the file moves
  `backlog/ → active/` and goes straight to implementation, then to `done/`.
- `/{{PREFIX}} --feature --next --chain` — Codex-only backlog conveyor. It chooses the same SPEC as
  `--next`; after a successful `done` transition it opens one fresh local Codex task for the next
  runnable SPEC, using the same checkout, model, and reasoning effort. It never creates a worktree
  or Git branch, and it stops cleanly when the board is drained or any gate blocks.
- A single-SPEC feature skips the board — the SPEC is shown inline in chat as before.
- `/{{PREFIX}} --discuss <topic>` — still writes a single `<slug>.md` brainstorm artifact at the
  root (format at the bottom). When a brainstorm graduates into a multi-SPEC plan, those SPECs go
  to `backlog/`.

## Naming (epics)

Group the SPECs of one large feature ("epic") by a shared filename prefix + an order number:

```
backlog/<epic-slug>-00-overview.md   # epic index: goal, ordered SPEC list, dependencies, cross-cutting notes
backlog/<epic-slug>-01-<short>.md    # SPEC 1
backlog/<epic-slug>-02-<short>.md    # SPEC 2
...
```

A standalone (non-epic) SPEC is just `<slug>.md` in the relevant folder.

## SPEC file format

```markdown
# <SPEC title>
Epic: <epic-slug | —>
Order: <NN of MM | —>
Status: draft | backlog | active | done   # draft = auto-written by --spec (unreviewed); else mirrors the folder
Depends-on: <epic-NN | —>
Risk-signals: <comma-separated | —>
Acceptance-matrix: <dim=v1,v2; dim=v1,v2,v3 | —>
Date: YYYY-MM-DD

## SPEC
=== SPEC ===
<the full SPEC block — TASK / WHAT / LAYERS / CHANGED_HINT / TEST_TYPES / CONSTRAINTS>
=== END SPEC ===

## Gap / context
<one or two lines: the concrete gap this SPEC closes>

## Implementation links
- commit: <hash>      (filled when moved to done/)
- files:  <changed files>
```

### `Risk-signals:` — what the slice is about, declared once

A comma-separated subset of: `auth`, `entitlement`, `payment`, `security`, `privacy`,
`persistence`, `migration`, `di-wiring`, `navigation`, `concurrency`, `server-authoritative`,
`offline`, `cross-module`, `visual`. Use `—` when the slice carries none of them.

The risk router reads this line and routes model tier, semantic review, and the independent
critic from it. Without it the router has to infer risk from prose keywords, which is
language-bound: a SPEC describing session invalidation and bounded polling in a language the
keyword lists do not cover scored as routine work and went to the cheap route, and the cost came
back as repeated semantic-review cycles. Whoever plans the slice already knows these facts —
writing them down is cheaper and more reliable than re-deriving them from wording.

Declaring a signal that is not really present is not free: it buys a stronger model and an extra
critic pass. Declare what the slice actually touches.

### `Acceptance-matrix:` — how many behaviours this slice carries

The dimensions whose values change the expected outcome, with their values:

```
Acceptance-matrix: role=owner,participant; state=active,grace,expired; transport=rpc,realtime
```

Semicolons separate dimensions, commas separate that dimension's values. `—` means the slice has
one behaviour for everyone in every state. Typical dimensions: actor/role, entity or entitlement
state, transport or data source, error class.

The product of the value counts is the slice's acceptance surface, and
`{{PREFIX}}-spec-complexity.sh` refuses to start implementation when it exceeds the budget
(default 24 cells, `acceptanceCellBudget` in `.claude/mp/config.json`). The same expansion is
frozen to a file that semantic review reports coverage against, so review converges against a
fixed list instead of resampling a different facet each pass.

Why it is declared rather than inferred: a SPEC whose real surface was 2 roles × 5 states × 2
transports × 3 error classes — 60 cells — passed as one slice and took eight review cycles. Nothing
derivable from its prose or its `CHANGED_HINT` showed the size; `CHANGED_HINT` named two modules
while the work crossed seven plus a server grant. Whoever plans the slice knows these dimensions,
and writing them down is both the honest size estimate and the review's termination condition.

## Lifecycle

| When | Action |
|------|--------|
| `--spec <desc>` | write SPEC file(s) to `backlog/` with `Status: draft` — no approval gate (grooming) |
| `--feature <desc>` splits into ≥2 SPECs | write SPEC files into `backlog/` (+ overview) behind one y/N gate, promote the first |
| `--feature --next` / `--backlog <slug>` | take a backlog SPEC (already approved) → move `backlog/ → active/`, `Status: active`, run Phase 2 — Phase 0/1 skipped |
| `--feature --next --chain` (Codex) | same selection as `--next`; after a successful close, schedule one local same-directory Codex task only when another runnable SPEC remains |
| SPEC shipped (Verifier pass / push) | move `active/ → done/`, fill `commit` + `files`, set `Status: done` |

Moving a SPEC to `active/` never bypasses the human SPEC-approval gate — Phase 2 still waits for
the user's `y` before any agent runs.

## `--discuss` brainstorm artifact format (root-level `<slug>.md`)

```markdown
# <Topic, one-line restatement>
Status: brainstorm | spec-ready | in-progress | done
Date: YYYY-MM-DD

## Brainstorm output
<full BRAINSTORM block from {{PREFIX}}-architect — verbatim>

## Approved SPEC
<full SPEC block from /{{PREFIX}} --feature, or "(pending)">

## Implementation links
- commit: <hash>
- files: <list>
(or "(pending)")
```
