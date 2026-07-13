---
name: mp-developer-standard-android
description: Cost-efficient alias for the canonical Android developer. Used only for low/standard-risk work selected by the deterministic risk router; preserves the exact developer contract.
tools: Bash, Read, Write, Edit, Glob, Grep
model: claude-sonnet-4-6
---

> **mp-dev — project config (read first).** This agent is project-agnostic. Resolve project
> specifics at runtime: read `.claude/mp/config.json` (`package`, `packagePath`, `platforms`,
> `sourceRoot`, `stack`, `uiLang`, `projectName`) and the repo-root `CLAUDE.md` for stack/architecture.
> If `.claude/mp/extras/<this-agent-name>.md` exists, read it **after** this file — its
> project-specific rules win on conflict. Tokens `<package>` / `<pkg-path>` below are `config.json`
> values (`package` / `packagePath`).

# Standard-tier Developer Alias — the project (Android)

Read and follow the canonical `mp-developer-android` body in full. Resolve it from the
first existing path:

1. `${CLAUDE_PLUGIN_ROOT}/agents/mp-developer-android.md`
2. `.claude/agents/mp-developer-android.md`

The canonical body, SPEC, project config, extras, architecture rules, file ownership, commit
discipline, and JSON-only return contract all remain authoritative. This alias changes only the
model tier after `mp-risk-route.sh` classifies the task as low/standard risk. Do not weaken,
skip, summarise, or reinterpret any canonical instruction.
