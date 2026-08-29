# Handoff

Last session: Codex · 2026-08-29 · prepared **1.17.2** chain-autonomy fixes.

## DONE

- Fixed standard MP feature/bugfix push instructions: `git push origin HEAD` is the primary path,
  `GIT_TERMINAL_PROMPT=0` prevents hangs, and an explicit HTTPS `GITHUB_TOKEN` is only a fallback.
- Fixed Codex `--feature --next --chain`: `create_thread` receives the exact chain command as its
  required initial prompt; the new local task has no inherited turns/context and receives no second
  message. It still requires `main` and never creates a worktree or branch.
- Fixed the follow-on gate regression: a substantially delivered SPEC is auto-closed only after
  targeted evidence/tests pass, without asking the user to confirm a verified fact.
- Preserved `--unattended` across fresh Codex chain tasks, including natural-language "skip all
  human gates" instructions; added one safe retry for definitive pre-creation payload validation
  errors and telemetry for chain-handoff/staleness outcomes.
- Updated canonical templates, generated Claude/Codex marketplace trees, docs, tests, changelog,
  and version **1.17.2**.
- Refreshed Codex cache at `mp-dev/1.17.2`, and hot-patched active `mp-dev/1.17.0` and `1.17.1`
  runtime files.

## VERIFIED

- `bash tests/test-chain-contract.sh`
- `bash tests/test-github-push-contract.sh`
- `bash tests/test-render-properties.sh`
- `bash tests/test-bootstrap.sh`
- `bash tests/test-sync.sh`
- `bash tests/test-optimization-scripts.sh`
- `bash tests/test-proposals.sh`
- `bash tests/test-eval.sh`
- `bash lib/build-marketplace.sh --check-runtime` → 15 modes / 14 contracts
- `git diff --check` and Bash syntax checks passed.

## DECISIONS

- GitHub authentication belongs to the configured Git credential helper (`gh auth`, Git Credential
  Manager, or SSH); MP must not assume that a `GITHUB_TOKEN` environment variable exists.
- A successor chain task is independent but has one deliberate initial user message: the exact chain
  command required by the current Codex task API. An empty prompt plus follow-up is invalid.
- The chain still does not bypass destructive/outward gates (delivery, feedback, epic-close,
  verifier, push, or board-drained gates); unattended only carries advisory decisions forward.
- A definitive pre-creation argument validation failure is safe to repair once; an unknown outcome
  is never retried because it may already have created a successor task.

## NEXT

- Review and merge the chain-autonomy PR; after merge, keep the installed Codex cache on `1.17.2`
  (the active `1.17.0`/`1.17.1` paths are already hot-patched for immediate use).

## OWNER

Codex.

## BLOCKERS

None.
