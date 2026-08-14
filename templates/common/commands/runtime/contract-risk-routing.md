<!-- mp-runtime-contract: risk-routing -->

## Risk-based model and quality routing

Apply this contract before the first Developer call in `--feature`, `--phase`, or `--bugfix`.

### Prepare the routing input

Set `TASK` to `feature` or `bugfix`. Resolve an existing `SPEC_FILE`:

- backlog mode: use the active SPEC markdown file;
- phase-generated or inline feature/bugfix: persist the approved SPEC block to
  `.ai/local/{{PREFIX}}-current-spec.md` (operational, git-ignored context; never application
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
bash "{{AGENT_DIR}}/scripts/{{PREFIX}}-risk-route.sh" \
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

- `developer_tier=standard` → `DEVELOPER_AGENT={{PREFIX}}-developer-standard-android`;
- `developer_tier=powerful` → `DEVELOPER_AGENT={{PREFIX}}-developer-android`;
- `verifier=lite` → `VERIFIER_AGENT={{PREFIX}}-verifier-lite-android`;
- `verifier=full` → `VERIFIER_AGENT={{PREFIX}}-verifier-android`.

Feature work always uses the full verifier even if a malformed/custom route says lite. A bugfix may
use lite only on the router's low-risk path; every other bugfix uses full. For a platform without
the routed aliases, use its canonical powerful Developer and full Verifier.

Use `DEVELOPER_AGENT` for the initial implementation, TDD green phase, and the single auto-fix
retry. The post-implementation router result replaces the initial aliases before later steps.

### Semantic review and independent critic

After the deterministic reviewer passes, when `semantic_review=true`, spawn
`{{PREFIX}}-semantic-reviewer-android` with the approved SPEC file, scoped changed files, and
deterministic-review evidence. The prompt must require `pass`, `findings[]`, and `uncertainties[]`.
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
   (`{{PREFIX}}-runner-<platform>.sh --scope …`). Do not spend a full runner here — the full run is
   the final gate, not the discovery mechanism.
6. **Budget: two repair cycles.** If a third semantic pass still returns blockers, stop patching.
   Surface the accumulated finding IDs, spawn `{{PREFIX}}-architect` in `PREFLIGHT` mode for a
   design capsule over the disputed area, and put the capsule in front of the user as a gate before
   any further code. Continuing to patch past this point is how a slice turns into a multi-hour run.

Carry the ID ledger (`id`, `rule`, `status`, `cycle`) into the Verifier and the independent critic
so a finding that was silently dropped between cycles is visible instead of assumed handled.
