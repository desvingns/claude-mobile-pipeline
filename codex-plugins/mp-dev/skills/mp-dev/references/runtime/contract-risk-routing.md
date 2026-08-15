<!-- mp-runtime-contract: risk-routing -->

## Risk-based model and quality routing

Apply this contract before the first Developer call in `--feature`, `--phase`, or `--bugfix`.

### Size gate: is this one SPEC? (run first, costs seconds)

Before routing, before any agent, run:

```bash
bash "$MP_SCRIPTS/mp-spec-complexity.sh" \
  --spec "$SPEC_FILE" \
  --freeze ".ai/local/mp-matrix-<spec-slug>.md"
```

It reads the SPEC's `Acceptance-matrix:` line — the dimensions the behaviour actually crosses
(`role=owner,participant; state=active,grace,expired; transport=rpc,realtime`) — and returns the
size of their cross-product:

```json
{"ok":true,"verdict":"ok|warn|split_recommended|undeclared","cells":12,"cell_budget":24,
 "matrix_declared":true,"frozen_matrix":".ai/local/..."}
```

Act on `verdict`:

- **`ok`** — continue silently.
- **`warn`** — continue, and say in one line how many cells this SPEC carries. It is a forecast of
  more than one review cycle, not a problem.
- **`split_recommended`** — stop before the first Developer call. Show the cell count and the
  dimensions, then ask once: *"This SPEC's acceptance surface is N cells across D dimensions.
  Split it into smaller SPECs before implementing? (Y/n)"*. On `Y`, hand the SPEC back to
  `mp-planner` for a split and re-run this gate on the first resulting SPEC. On `n`,
  proceed as written and append `size_override=1` to the developer telemetry metric.
- **`undeclared`** — the SPEC predates this field or the planner omitted it. Do **not** guess a
  verdict from prose and do not block: derive the dimensions yourself from the SPEC's acceptance
  criteria, write the `Acceptance-matrix:` line into the SPEC file, and re-run the gate once.

This gate is thirty seconds against the failure it prevents. A slice whose acceptance surface was
2 roles × 5 entitlement states × 2 transports × 3 error classes — 60 cells — was routed as one
SPEC and took eight semantic-review cycles, each returning findings that were all new, because no
review loop can converge a search space that was never bounded. Note that `CHANGED_HINT` is not
used here: on that same run it named two modules while the work crossed seven plus a server grant,
so every estimate derived from it ranked the epic's worst SPEC as one of its smallest. What the
SPEC declares about behaviour is the honest measure; what it guesses about files is not.

### Prepare the routing input

Set `TASK` to `feature` or `bugfix`. Resolve an existing `SPEC_FILE`:

- backlog mode: use the active SPEC markdown file;
- phase-generated or inline feature/bugfix: persist the approved SPEC block to
  `.ai/local/mp-current-spec.md` (operational, git-ignored context; never application
  source) and use that path.

**Declare the risk signals before routing.** The router reads a `Risk-signals:` line from the
SPEC file (vocabulary in `.claude/specs/README.md`). A backlog SPEC carries it from the planner.
For a phase-generated or inline SPEC you are the one persisting the file, so write the line
yourself from what the slice actually touches — session/auth lifecycle, entitlement, persistence
or migration, the DI graph, navigation, concurrency or a cancellation budget, cross-module data
flow, server-authoritative state, visual/device work — or `—` when none apply. Without it the
router falls back to prose keywords, which depend on the language the SPEC happens to be written
in; that fallback routed a security-sensitive cross-layer slice to the cheap developer with no
independent critic, and it was paid back as four semantic-review cycles.

Run through Bash:

```bash
bash "$MP_SCRIPTS/mp-risk-route.sh" \
  --task feature|bugfix \
  --spec "$SPEC_FILE" \
  [--visual] \
  [--changed "$path"]...
```

Add `--visual` for clone/UI/fit/manifest or explicitly visual/device work. Before the first
Developer call omit `--changed`; after implementation, run the router exactly once more with one
repeatable `--changed` argument per file in the scoped task diff.

Parse its one JSON line:

```json
{
  "risk": "...",
  "developer_tier": "standard|powerful",
  "semantic_review": true,
  "verifier": "lite|full",
  "independent_critic": false
}
```

Do not require `jq`. If the script is absent, errors, or returns invalid/unknown fields, use the
safe fallback: `developer_tier=powerful`, deterministic reviewer required,
`semantic_review=true`, `verifier=full`, and `independent_critic=true`.

### Resolve agents

For Android:

- `developer_tier=standard` → `DEVELOPER_AGENT=mp-developer-standard-android`;
- `developer_tier=powerful` → `DEVELOPER_AGENT=mp-developer-android`;
- `verifier=lite` → `VERIFIER_AGENT=mp-verifier-lite-android`;
- `verifier=full` → `VERIFIER_AGENT=mp-verifier-android`.

Feature work always uses the full verifier even if a malformed/custom route says lite. A bugfix may
use lite only on the router's low-risk path; every other bugfix uses full. For a platform without
the routed aliases, use its canonical powerful Developer and full Verifier.

Use `DEVELOPER_AGENT` for the initial implementation, TDD green phase, and the single auto-fix
retry. The post-implementation router result replaces the initial aliases before later steps.

### Semantic review and independent critic

After the deterministic reviewer passes, when `semantic_review=true`, spawn
`mp-semantic-reviewer-android` with the approved SPEC file, the frozen acceptance matrix
from the size gate, scoped changed files, and deterministic-review evidence. The prompt must
require `pass`, `findings[]`, `uncertainties[]`, and `coverage` (see the repair loop, step 6).
Every finding keeps the existing `severity`, `file`, `line`, `rule`, `evidence`, and `fix` fields.
For every `severity:"blocker"`, also require non-empty `explanation`, `user_case`, `impact`, and
`blocking_reason` fields; the blocker must be independently understandable without source-code
context, and `fix` must state the exact correction direction. Warnings may use the compact
technical format.

Validate this conditional blocker contract before continuing. A blocker missing any required
context field is an invalid semantic-review response and gets the standard one retry from
`contract-execution.md`; if the retry is still invalid, stop and surface the contract failure.
A semantic failure blocks Tester/Runner. When surfacing it, render every blocker as a
self-contained report containing, in order: plain-language explanation, Given/When/Then (or
equivalent) user case, user/business impact, why it blocks shipping, exact correction direction,
then the original technical evidence (`file`, `line`, `rule`, `evidence`, `fix`) without omission or
paraphrase. Pass the whole original payload forward as evidence. These requirements apply to the
initial semantic review and the independent critic.

When `independent_critic=true`, after the final Runner result and before Verifier run one
additional semantic-reviewer pass with a fresh evidence packet containing only the SPEC, file
paths/hashes, scoped diff, and deterministic test/review artifacts—never the first semantic
reviewer's conclusion. A critic failure blocks the chain.
Validate each structured response under `contract-execution.md`; no semantic pass may auto-fix code.

### Escalation ratchet (the reviewer's own risk read counts)

The semantic reviewer returns its own `risk`. When it reports `risk:"high"`, or returns any
`severity:"blocker"`, the route ratchets up for the **remainder of this SPEC** and never back down:
set `DEVELOPER_AGENT` to the powerful developer, `independent_critic=true`, and `VERIFIER_AGENT`
to the full verifier. Say so in one line when you surface the findings, and append
`route_escalated=1` to the `semantic-reviewer` telemetry metric.

Rationale: the router scores a SPEC before any code exists, so it can be wrong. The reviewer has
read the actual diff. A run where the reviewer said `risk=high` four times while the cheap
developer kept patching is a route that stayed wrong for an hour because nothing fed the reviewer's
verdict back into it.

### Semantic repair loop

A semantic failure blocks Tester/Runner. Repair it as follows — the loop is a contract, not an
improvisation, because "fix the findings, re-review, repeat" rediscovers one facet of the same
design problem per cycle and pays a full agent round-trip for each.

1. **Give every finding a stable ID** of the form `<RULE>-<NNN>` — `AUTH-STATE-001`,
   `DI-CYCLE-001`, `TEST-CLOCK-001`, `POLL-BUDGET-001` — derived from the finding's `rule` field.
   IDs are assigned once and reused across every later cycle of this SPEC.
2. **Dispatch ALL findings in ONE batch** to the same Developer agent when it is still healthy
   (a fresh agent only after a hang, an invalid architecture, or contaminated context). Never send
   one cluster, wait, and send the next.
3. **Require a holistic re-audit, not a line fix.** The repair prompt must say, verbatim in intent:
   *re-audit the whole implementation against the entire SPEC and the semantic checklist — not only
   the listed lines. Resolve dependency direction, lifecycle ownership, stale state, concurrency
   and publication order, cancellation, and timeout budget in one patch.* Findings are symptoms of
   a design decision; repairing them one at a time re-derives the same decision repeatedly.
4. **Require a regression test per finding** before re-review, and require the Developer to return
   `resolved_findings`: `[{"id":"AUTH-STATE-001","status":"fixed|regressed|superseded","note":"one line"}]`
   alongside its normal `{"changed_files":[...],"commit":"hash"}` payload. An ID that reappears in a
   later cycle with `status:"fixed"` is a regression and must be surfaced as such.
5. **Re-verify narrowly before re-review**: compile the affected modules and run the scoped tests
   (`mp-runner-<platform>.sh --scope …`). Do not spend a full runner here — the full run is
   the final gate, not the discovery mechanism.
6. **Review against the frozen matrix, not from scratch.** Pass the frozen matrix file from the
   size gate to every semantic pass and require, alongside `findings[]`, a `coverage` object:
   `{"total":N,"covered":M,"uncovered":["role=owner · state=grace", ...]}`. A pass may add a cell
   it discovers is missing, but it may not silently re-decompose the problem. Surface
   `covered/total` in one line each cycle.

   This is what makes the loop terminate. Left unbounded, each pass samples a different facet of
   the same design and returns findings that are all new — one run produced `STATE-001..008`,
   `SECURITY-001..004` and `TESTS-001..011` across eight cycles without repeating a single ID,
   which reads like progress and is actually a random walk. Against a fixed list, "three cycles and
   still failing" becomes the answerable question *which cells are still uncovered* instead of the
   unanswerable *what else might be wrong*.
7. **Budget: two repair cycles.** If a third semantic pass still returns blockers, stop patching.
   Surface the accumulated finding IDs and the uncovered cells, then spawn `mp-architect`
   in `PREFLIGHT` mode for a design capsule over the disputed area. Route on the capsule's
   `VERDICT`:

   - **`PATCH ALLOWED`** — continue automatically. Dispatch one capsule-informed repair batch,
     announce in one line that the capsule was applied without a gate, and record `gate_auto=1` on
     the developer event. Do **not** stop for approval: the capsule's whole purpose is to settle
     the design question, and asking a human to confirm a decision the architect already made
     costs hours for no added information.
   - **`DESIGN DECISION REQUIRED`** — this is a real gate. Put the capsule and its alternatives in
     front of the user and wait. Record `human_wait_ms` on the resuming event.

   After the capsule batch, the two-cycle budget **does not reset**: it becomes one final cycle. If
   the next semantic pass still returns blockers, stop and hand off — write the finding ledger, the
   uncovered cells, and the capsule into the SPEC's `## Handoff` section, and leave the SPEC in
   `active/`. Do not keep patching.

   Rationale, from a measured run: an unconditional gate here consumed 4 h 28 min of a 6 h 50 min
   SPEC — 65% of its wall clock — waiting for a human to approve a capsule whose own verdict was
   that no user decision was needed. The budget stops runaway patching; it must not manufacture
   overnight waits.

### Unattended runs

When the user starts the pipeline with `--unattended` (or says the run is unattended), every
**non-destructive** gate in this contract proceeds on its recommended default instead of waiting:
the size gate takes `Y` (split), and `PATCH ALLOWED` capsules already continue on their own. Each
auto-taken gate is logged in one line and collected into a "decisions taken while unattended"
summary at the end of the run. Gates that are destructive or push work outward — the SPEC approval
itself, `git push`, anything the user is asked to confirm elsewhere — are **never** auto-taken;
they stop the run and wait, as always.

### Agent liveness

A semantic pass that has produced no output for **10 minutes** is treated as unhealthy, not slow.
On that threshold: interrupt once, and re-dispatch to a fresh agent with the reduced evidence
packet (SPEC + frozen matrix + changed-file list + previous finding IDs — not the full diff).
If the retry also stalls, record `verdict:"partial"` with `stalled=1` and fall back to the
remaining deterministic gates rather than blocking the chain indefinitely. Recorded semantic
passes have run 500–700 s legitimately, so the threshold sits well above healthy latency; runs
that hang past it have needed a manual interrupt every time, and the wait was never recoverable
work.

Carry the ID ledger (`id`, `rule`, `status`, `cycle`) into the Verifier and the independent critic
so a finding that was silently dropped between cycles is visible instead of assumed handled.
