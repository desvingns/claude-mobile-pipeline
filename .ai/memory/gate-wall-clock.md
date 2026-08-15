# A gate that blocks is a cost, and it is usually the largest one

Measured on `plus-subscription-gating-05` (MyMoney, pipeline 1.14.0): recorded agent time was
74.7 min out of a 410 min telemetry window — **18%**. The single largest item was one human
approval gate at 268 min, **65%** of the window, and the capsule it was gating had already
concluded that no user decision was needed. A further 2 h 52 min of commits fell outside
telemetry entirely.

**Why this matters:** optimising an agent or a script buys seconds; the deterministic gates
improved in 1.14.0 totalled 123 s across that whole SPEC. Optimising *when the pipeline stops*
buys hours. Before tuning anything for speed, measure what fraction of elapsed time was spent
executing at all — if instrumentation covers 18% of the window, every speed conclusion drawn
from it is about the wrong 18%.

**How to apply:**

- Blocking is asymmetric. An unnecessary gate costs hours of wall clock; letting a
  well-specified decision proceed costs at most one more review cycle. Gate on
  *destructive or outward-facing* actions, never on "the model is not fully confident".
- Any agent that can trigger a gate must return an explicit verdict field saying whether a
  human decision is genuinely required, and must be told the cost asymmetry.
- Record human wait as its own metric. Agent time, orchestration and waiting for a sleeping
  human are three problems with three fixes; one `duration_ms` blurs them into a diagnosis of
  "slow tooling".
- Offer an unattended mode. An advisory gate during an overnight run is not a safety feature.

See also [[gate-liveness]] — a green gate is not evidence a gate ran; this is its sibling:
a *live* gate is not evidence the gate was worth stopping for.
