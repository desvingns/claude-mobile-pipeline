---
name: mp-dev
description: Run the MP Dev mobile development pipeline through Codex. Use when the user invokes $mp, /mp, mp-dev, or asks for MP feature, bugfix, discuss, spec, coverage, device, fit, plan, phase, check, improve, or reflect workflows.
---

# MP Dev Pipeline for Codex

Use this skill as a thin Codex bridge over the canonical Claude `mp-dev` pipeline. Keep project-specific behavior in the shared project files, not in a forked Codex-only copy.

## Startup

1. Read project guidance first: `AGENTS.md`, then `CLAUDE.md` if present.
2. Read shared MP project inputs:
   - `.claude/mp/config.json`
   - `.claude/mp/extras/*.md`
   - `.claude/specs/README.md` when using the backlog board
   - `docs/implementation_plan/PROGRESS.md` when the project has phase-plan workflows
3. Resolve the compact runtime beside this skill:
   - read `references/runtime/router.md` first;
   - select exactly one mode through the router's dispatch table; `manifest.tsv` is a packaging
     integrity marker, not runtime context;
   - read that mode runbook and only the `contract-*.md` files named in its metadata;
   - never preload every runbook. This lazy-loading boundary is part of the token budget.
4. Resolve `MP_SCRIPTS`: prefer project `.codex/scripts/`, then `scripts/` beside this SKILL.md,
   then project `.claude/scripts/` as a legacy fallback. A runtime command written as
   `$MP_SCRIPTS/mp-*.sh` means the selected absolute directory, not a shell environment dependency.
5. If the packaged runtime is absent, fall back to the newest Claude plugin
   `commands/mp.md` (`%USERPROFILE%/.claude/plugins/cache/mobile-pipeline/mp-dev/<version>/` on
   Windows, `~/.claude/plugins/cache/mobile-pipeline/mp-dev/<version>/` on POSIX, or
   `claude-plugins/mp-dev/commands/mp.md` inside this checkout). Stop before implementation only
   when neither runtime exists.
6. Interpret `$mp` and `/mp` as the Codex equivalent of the selected `/mp` workflow.

Supported modes include `--feature`, `--bugfix`, `--discuss`, `--spec`, `--coverage`, `--device`, `--fit`, `--plan`, `--phase`, `--check`, `--improve`, and `--reflect`. `--chain` is valid only as
`$mp --feature --next --chain`: after a successful SPEC close, follow the runtime's Codex hand-off
contract to fork one local same-directory task and send it the same command. Never substitute a
worktree, Git branch, or a newly selected model/effort.

## Native Agents

Use native project shims from `.codex/agents/mp-*.toml` when they exist. Each shim must read the matching canonical Claude agent body from the `mp-dev` plugin cache, then `.claude/mp/extras/<agent>.md` if present.

Read `references/codex-agent-shims.md` when installing, auditing, or repairing the per-project shim roster. If the shims were created in the current Codex session, a fresh Codex session may be needed before the runtime can spawn the new agent types.

Preserve canonical output contracts exactly: JSON-only for implementation, test, review, run, verify, docs, plan, improve, and reflect agents; one `=== BRAINSTORM ===` block for `mp-architect`. Retry invalid structured output once, then stop.

## Bash Compatibility

Codex environments may not have `bash` in `PATH`. If Bash is absent, do not require the Claude deterministic `.sh` scripts. Use native `mp-reviewer-android` and `mp-runner-android` shims directly, or perform the equivalent read-only checks when the mode is diagnostic.

`mp-runner-instrumented-android` is the only MP Dev role that may invoke a PowerShell host-AVD helper, and only when project guidance or `.claude/mp/extras/mp-runner-instrumented-android.md` explicitly names that helper.

## Sync Rules

Project-specific improvements go into `.claude/mp/extras/*` first so Claude and Codex consume the same overrides. Use `$mp --improve` or `$mp --reflect` for plugin-level improvements that belong in `mobile-pipeline`.

Claude and Codex may both use `.claude/specs/{backlog,active,done}`, but only one agent should implement a given active SPEC at a time. Parallel work is allowed only for explicitly disjoint backlog SPECs.
