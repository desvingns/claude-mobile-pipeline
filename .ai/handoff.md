# Handoff

Last session: Codex · 2026-08-22 · prepared **1.17.1** reliability fixes.

## DONE

- Fixed standard MP feature/bugfix push instructions: `git push origin HEAD` is the primary path,
  `GIT_TERMINAL_PROMPT=0` prevents hangs, and an explicit HTTPS `GITHUB_TOKEN` is only a fallback.
- Fixed Codex `--feature --next --chain`: `create_thread` receives the exact chain command as its
  required initial prompt; the new local task has no inherited turns/context and receives no second
  message. It still requires `main` and never creates a worktree or branch.
- Updated canonical templates, generated Claude/Codex marketplace trees, docs, tests, CI, changelog,
  and version **1.17.1**.
- Refreshed Codex cache at `mp-dev/1.17.1` and hot-patched the active `mp-dev/1.17.0` runtime files.

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
- The chain still does not bypass delivery, feedback, epic-close, verifier, push, or board-drained gates.

## NEXT

- Review the reliability branch/PR and merge it into `main`; after merge, the marketplace source and
  Codex cache are already aligned at `1.17.1`.

## OWNER

Codex.

## BLOCKERS

None.
