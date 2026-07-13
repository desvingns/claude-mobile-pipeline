# Token, quality, and memory optimization

Version 1.12 makes token spend proportional to task risk while retaining the pipeline's hard gates.
The strategy is not a blanket model downgrade: deterministic work becomes cheaper, context becomes
smaller, and expensive independent judgment is added only where it materially improves confidence.

## Measured fixed-context reduction

The canonical `/mp` command changed from an 83,140-character monolith (~20.8k tokens by chars/4)
to a 3,485-character router (~0.9k tokens; ~1.0k after marketplace frontmatter), a 95.4% reduction
in context paid on every invocation. One mode runbook plus its declared shared contracts is loaded
on demand. Measured complete working sets range from ~2.3k tokens (`--check`) to ~12.6k
(`--feature`), a 39–89% reduction depending on mode.

`lib/build-marketplace.sh --check-runtime` protects the split: 15 modes, 14 contracts, the original
heading/flag inventory, human gates, and structured payload rules must remain reachable. This keeps
the saving structural rather than relying on a shorter but lossy prompt.

## Risk-based spend

`<prefix>-risk-route.sh` scores persistence/migrations, security/payments, wiring/build changes,
concurrency, cross-layer scope, broad diffs, and visual/device evidence.

| Route | Developer | Extra judgment | Verifier |
|---|---|---|---|
| low-risk bugfix | standard tier | deterministic review | lite |
| routine feature / standard risk | standard tier | semantic review when signalled | full |
| high risk | powerful tier | semantic review + fresh independent critic | full |
| helper failure / invalid JSON | powerful tier | semantic review + critic | full |

The standard Developer is an alias over the full canonical contract, not a reduced instruction set.
The semantic reviewer ignores formatting/mechanical checks already covered deterministically and
looks only for behavioural, state, persistence, security, compatibility, and stale-test risks.

## MP Spec economics

- Phase fingerprints include source inputs, prompt/model assignment, and validated output presence.
  File existence alone is never a cache hit.
- Specialists receive `pipeline/evidence/core.json` plus one owned rubric, not raw conversation and
  every analyzer payload.
- NFR, accessibility, and risk always run. Security/privacy and analytics calls are conditional,
  but explicit low-risk/disabled artifacts are still generated, so bundle shape never degrades.
- Mechanical schema/ID/link/coverage failures are routed by `spec-preflight.sh` before the frontier
  evaluator. Evaluator retries target only failed classes and owning artifacts.
- `--budget lean|balanced|max` changes model/critic spend, never mandatory artifacts, traceability,
  blocker handling, or the two human gates.

`spec-usage.sh` distinguishes provider-reported tokens from chars/4 estimates and records model,
reasoning effort, cached/reasoning tokens, duration, retry, cache hit, and correlation ID. Compare
budgets using accepted FR/US output, not raw token totals alone.

## Memory and second brain

The layers have deliberately asymmetric authority:

1. Project-local `.ai/memory/`, handoff, task index, and `.claude/mp/extras/` own project facts.
2. Three small brain core files may be read at session start.
3. Everything else is selected on demand through `brain/INDEX.md`; the helper defaults to a compact
   budget and enforces a 1,600-token ceiling.
4. Cross-project/user lessons are fingerprinted candidates appended only to `brain/inbox/`.
   Curated `core/`, `domains/`, `pipelines/`, and `projects/` are never agent-written; `/brain promote`
   is the human gate and leaves a provenance receipt.

The compact cross-project digest is read first; its raw evidence appendix is opened only for a
candidate under review. An unchanged corpus produces no new digest and a no-signal heartbeat stays
silent.

## Learning and validation loop

Run telemetry records actual usage when exposed, otherwise an explicitly labelled estimate, along
with cache, reasoning, cost, duration, retry, and correlation fields. Retro reports flag telemetry
dormancy so missing instrumentation is not mistaken for cheap/reliable execution. Low-feedback
events become deterministic eval candidates; changes remain human-gated proposals with applied or
rejected archive receipts.

Useful local gates:

```bash
bash lib/build-marketplace.sh --check-runtime
bash tests/test-render-properties.sh
bash tests/test-optimization-scripts.sh
bash tests/test-brain-memory.sh
bash tests/test-sync.sh
bash tests/test-selfimprove.sh
bash tests/test-proposals.sh
bash tests/test-eval.sh
bash eval/runner.sh
```

After canonical edits, regenerate marketplace adapters, run both incremental sync cursors, smoke a
throwaway bootstrap, and finish with `scripts/graphify-update-canonical.sh`.
