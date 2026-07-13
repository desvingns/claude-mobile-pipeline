# Codex mp-dev Agent Shims

Use this reference when installing or auditing native `.codex/agents/mp-*.toml` wrappers for a project.

## Required Roles

Install one TOML shim for each canonical Claude `mp-dev` agent:

`mp-architect`, `mp-coverage-android`, `mp-developer-android`, `mp-developer-standard-android`,
`mp-docs`, `mp-fit-android`, `mp-improve`, `mp-intake`, `mp-knowledge`, `mp-maintainer`,
`mp-phase-planner`, `mp-planner`, `mp-reflect`, `mp-reviewer-android`,
`mp-semantic-reviewer-android`, `mp-runner-android`, `mp-runner-instrumented-android`,
`mp-tester-android`, `mp-ui-designer-android`, `mp-verifier-android`,
`mp-verifier-lite-android`.

Each TOML must read the matching Claude body from the user's Claude plugin cache, then `.claude/mp/extras/<agent>.md` if present. Prefer the newest cache directory under:

- Windows: `%USERPROFILE%/.claude/plugins/cache/mobile-pipeline/mp-dev/<version>/agents/<agent>.md`
- POSIX: `~/.claude/plugins/cache/mobile-pipeline/mp-dev/<version>/agents/<agent>.md`

For local marketplace development inside this repo, use `claude-plugins/mp-dev/agents/<agent>.md`.

## Model and Sandbox Map

| Agent | Model | Effort | Sandbox |
|---|---:|---:|---|
| `mp-architect` | `gpt-5.4` | `high` | `read-only` |
| `mp-coverage-android` | `gpt-5.4-mini` | `low` | `read-only` |
| `mp-developer-android` | `gpt-5.6` | `high` | `workspace-write` |
| `mp-developer-standard-android` | `gpt-5.4` | `high` | `workspace-write` |
| `mp-docs` | `gpt-5.4` | `high` | `workspace-write` |
| `mp-fit-android` | `gpt-5.6` | `high` | `read-only` |
| `mp-improve` | `gpt-5.4` | `high` | `workspace-write` |
| `mp-intake` | `gpt-5.4` | `high` | `workspace-write` |
| `mp-knowledge` | `gpt-5.4` | `high` | `workspace-write` |
| `mp-maintainer` | `gpt-5.4` | `high` | `workspace-write` |
| `mp-phase-planner` | `gpt-5.4` | `high` | `workspace-write` |
| `mp-planner` | `gpt-5.4` | `high` | `workspace-write` |
| `mp-reflect` | `gpt-5.4` | `high` | `workspace-write` |
| `mp-reviewer-android` | `gpt-5.4-mini` | `medium` | `read-only` |
| `mp-semantic-reviewer-android` | `gpt-5.4` | `high` | `read-only` |
| `mp-runner-android` | `gpt-5.4-mini` | `low` | `workspace-write` |
| `mp-runner-instrumented-android` | `gpt-5.4-mini` | `low` | `workspace-write` |
| `mp-tester-android` | `gpt-5.4` | `high` | `workspace-write` |
| `mp-ui-designer-android` | `gpt-5.4` | `high` | `workspace-write` |
| `mp-verifier-android` | `gpt-5.4-mini` | `medium` | `read-only` |
| `mp-verifier-lite-android` | `gpt-5.4-mini` | `low` | `read-only` |

Implementation (both tiers), planning, docs, improve, intake, knowledge, reflect, tester, and
UI-designer roles need `workspace-write`. Deterministic reviewer, semantic reviewer, both verifiers,
coverage, architect, and fit roles are read-only. Runner roles may use `workspace-write` only for
build artifacts and reports.

## Extra Instructions by Role

- `mp-runner-android`: if Bash is unavailable, run equivalent Gradle checks directly through Codex shell execution instead of invoking the Claude script.
- `mp-reviewer-android`: if Bash is unavailable, use the native reviewer shim directly instead of invoking the Claude script.
- `mp-runner-instrumented-android`: may call a PowerShell host-AVD helper only when project guidance or its extras file explicitly allows it.
- `mp-docs`: project extras may make this role inert when phase or release state is owned by another document.

After creating new shims, run a static TOML/path check. Then start a fresh Codex session before relying on `spawn_agent`, because the current runtime may not reload newly added agent types.
