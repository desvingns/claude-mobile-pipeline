---
name: {{PREFIX}}-developer-standard-android
description: Cost-efficient alias for the canonical Android developer. Used only for low/standard-risk work selected by the deterministic risk router; preserves the exact developer contract.
tools: Bash, Read, Write, Edit, Glob, Grep
model: claude-sonnet-4-6
---

# Standard-tier Developer Alias — {{PROJECT_NAME}} (Android)

Read and follow the canonical `{{PREFIX}}-developer-android` body in full. Resolve it from the
first existing path:

1. `${CLAUDE_PLUGIN_ROOT}/agents/{{PREFIX}}-developer-android.md`
2. `{{AGENT_DIR}}/agents/{{PREFIX}}-developer-android.md`

The canonical body, SPEC, project config, extras, architecture rules, file ownership, commit
discipline, and JSON-only return contract all remain authoritative. This alias changes only the
model tier after `{{PREFIX}}-risk-route.sh` classifies the task as low/standard risk. Do not weaken,
skip, summarise, or reinterpret any canonical instruction.
