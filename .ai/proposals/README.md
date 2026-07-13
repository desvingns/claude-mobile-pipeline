# Improvement proposal lifecycle

Proposal artifacts are append-safe review inputs, not disposable scratch files. A queued proposal
uses the same basename for `.patch`, `.changelog`, and optional `.md` / `.meta` files directly under
`.ai/proposals/`.

Lifecycle:

1. `queued` — artifacts are present at `.ai/proposals/<slug>.*` and await a human gate.
2. `applied` — the approved patch was applied to an improvement branch.
3. `archived` — all source artifacts were moved to
   `.ai/proposals/archive/applied/<timestamp>/`, alongside `<slug>.lifecycle.json`.
4. `rejected` — a human-declined proposal is moved to
   `.ai/proposals/archive/rejected/<timestamp>/`, also with a lifecycle receipt.

Commands:

```bash
# Drain every queued proposal through one gated batch PR.
bash <plugin-root>/scripts/mp-improve-drain.sh <mp-repo>

# Human-gated terminal decisions; neither command deletes an artifact.
bash <plugin-root>/scripts/mp-improve-drain.sh <mp-repo> --reject <slug> --reason "..."
bash <plugin-root>/scripts/mp-improve-drain.sh <mp-repo> --archive-applied <slug> --reason "..."
```

Queue readers inspect only top-level `*.patch`; archived proposals cannot be drained twice. Lifecycle
receipts retain the outcome, reason, timestamp, and the full `queued → outcome → archived` trail.
