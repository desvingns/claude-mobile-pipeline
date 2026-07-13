<!-- mp-runtime-mode: upgrade -->
<!-- mp-runtime-contracts: startup execution rules -->

## Workflow: --upgrade

Reviews and optionally updates model assignments across all pipeline agent files.
Run this when Anthropic releases a new Claude model family version.
For future Codex-native dev shims, use the same fast/standard/powerful tier intent with explicit
`model` + `model_reasoning_effort` fields instead of inheriting the parent session.

### Phase 1 — Invoke maintainer

Parse optional argument: comma-separated model IDs after `--upgrade` (e.g. `--upgrade claude-sonnet-4-7,claude-haiku-4-6`).

Spawn agent `{{PREFIX}}-maintainer` with prompt:
```
mode: models
[new_models: <comma-separated list from args, omit line if no args given>]
```

The maintainer will display current assignments, ask the user about each affected tier, apply confirmed changes, and print a summary. No further orchestrator action is needed.

---
