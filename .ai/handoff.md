# Handoff

Last session: Codex · 2026-08-21 · released **1.16.0** on `main` (`18eaf3b`).

## DONE

- Added the strict backlog conveyor selector: `--feature --next --chain`.
  - `--next` still resumes `active/` first, otherwise chooses the lowest ordered runnable backlog
    SPEC; `--chain` never changes this resolution.
  - Any other use of `--chain` (another mode, no `--next`, or `--backlog`) is rejected.
  - After a successful `active/ → done/` move, required epic-close and post-ship moves run first.
    A failure, unfinished human gate, or epic-review gap never creates another task.
  - With another runnable backlog SPEC, Codex forks one `same-directory` task, preserving the
    selected model and reasoning effort, and sends it `$mp --feature --next --chain`.
  - It confirms the checkout is exactly `main`; it never switches branches, creates a Git branch,
    or creates a worktree. A drained board creates no empty task.
- Kept Claude safe and explicit: generated Claude runtime reports the next command but has no Codex
  task-API instruction.
- Bumped `VERSION` and all generated marketplace manifests to **1.16.0**; rebuilt
  `claude-plugins/` and `codex-plugins/` from canonical templates.
- Added `tests/test-chain-contract.sh`, invoked in CI. It checks selector validity, Codex-only
  generated hand-off instructions, no Claude/tool-marker leakage, and runtime validation.

## VERIFIED

- `bash tests/test-chain-contract.sh`
- `bash tests/test-render-properties.sh`
- `bash tests/test-bootstrap.sh`
- `bash tests/test-sync.sh`
- `bash tests/test-optimization-scripts.sh`
- `bash lib/build-marketplace.sh --check-runtime` → 15 modes / 14 contracts
- Marketplace regeneration completed twice without generated-marker or placeholder leaks.

## DECISIONS

- A Codex `same-directory` task fork is the hand-off primitive: it retains task model/effort while
  staying on the exact local checkout. `create_thread` would use the configured default when model
  and effort are omitted, not necessarily the current selection.
- The chain does not bypass existing delivery, feedback, epic-close, verifier, or push gates. If a
  closing action needs the user, it pauses there and only schedules the successor after the action
  finishes cleanly.
- A final/runnable-board check prevents a visibly useless empty Codex task after the last SPEC.

## NEXT

- Refresh/reinstall `mp-dev@mobile-pipeline` in the Codex app after the source update if its plugin
  cache remains pinned to 1.15.0; the repository now contains the 1.16.0 Codex marketplace artifact.

## OWNER

Codex.

## BLOCKERS

None in the repository. The desktop app exposes no direct plugin-install/update operation to this
task; its existing local cache was observed at 1.15.0.
