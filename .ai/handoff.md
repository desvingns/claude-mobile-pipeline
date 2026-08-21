# Handoff

Last session: Codex · 2026-08-21 · prepared **1.17.0** for `main`.

## DONE

- Added the strict backlog conveyor selector: `--feature --next --chain`.
  - `--next` still resumes `active/` first, otherwise chooses the lowest ordered runnable backlog
    SPEC; `--chain` never changes this resolution.
  - Any other use of `--chain` (another mode, no `--next`, or `--backlog`) is rejected.
  - After a successful `active/ → done/` move, required epic-close and post-ship moves run first.
    A failure, unfinished human gate, or epic-review gap never creates another task.
  - With another runnable backlog SPEC, Codex resolves the current saved project and creates one
    fresh local task with `create_thread`, an empty conversation, and no inherited task context,
    then sends it `$mp --feature --next --chain`.
  - It confirms the checkout is exactly `main`; it never switches branches, creates a Git branch,
    or creates a worktree. A drained board creates no empty task.
- Kept Claude safe and explicit: generated Claude runtime reports the next command but has no Codex
  task-API instruction.
- Bumped `VERSION` and all generated marketplace manifests to **1.17.0**; rebuilt
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

- A Codex `create_thread` task in the saved project with `environment: local` is the hand-off
  primitive: it starts with an empty conversation from the project's default `main` checkout.
  `fork_thread` is intentionally forbidden because it carries prior turns into the next SPEC.
- The chain does not bypass existing delivery, feedback, epic-close, verifier, or push gates. If a
  closing action needs the user, it pauses there and only schedules the successor after the action
  finishes cleanly.
- A final/runnable-board check prevents a visibly useless empty Codex task after the last SPEC.

## NEXT

- Refresh/reinstall `mp-dev@mobile-pipeline` in the Codex app after the source update if its plugin
  cache remains pinned to an older version; the repository now contains the 1.17.0 Codex marketplace artifact.

## OWNER

Codex.

## BLOCKERS

None in the repository. The desktop app exposes no direct plugin-install/update operation to this
task; the local cache is refreshed separately after the source release.
