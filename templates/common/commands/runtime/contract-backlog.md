<!-- mp-runtime-contract: backlog -->

## SPEC backlog board

`.claude/specs/` is a file-based task board for SPECs — full contract (layout, file format, lifecycle) in `.claude/specs/README.md`. It persists a **large feature that splits into several SPECs** so it is ordered and resumable across sessions, not stuck in one chat.

- `backlog/` — SPECs queued, not started (+ an `<epic-slug>-00-overview.md` index).
- `active/` — the SPEC being implemented now (normally one).
- `done/` — shipped SPECs, with `commit` + changed files filled in.
- A SPEC's **status is the folder it lives in**; an epic's SPECs share a filename prefix `<epic-slug>-NN-<short>.md` (NN = order).

**Lifecycle the orchestrator drives:** `--feature` Phase 1 writes a multi-SPEC feature's SPEC files into `backlog/` behind one y/N gate → `--feature --next` / `--feature --backlog <slug>` consumes an already-approved SPEC without a second approval question, first applying the staleness verification in `feature.md` → on starting a non-stale SPEC, move `backlog/ → active/` and run Phase 2 → on ship (Verifier pass / push), move `active/ → done/` and fill `commit` + `files` → when that ship was the epic's **last** SPEC, run the **Epic completion** review + close (below). Creating/moving these markdown files is a planning action the orchestrator may do directly; it never silently treats incomplete evidence as delivered.

### Epic completion (final review + close)

Run this **every time** a SPEC that belongs to an epic (filename `<epic-slug>-NN-<short>.md`) ships and moves `active/ → done/`. It exists because per-SPEC moves leave the epic's `<epic-slug>-00-overview.md` index stranded in `backlog/` — a finished epic must not keep files on the queue.

1. **Detect last SPEC.** The shipped SPEC is the epic's last when no `<epic-slug>-NN-*.md` file (NN ≥ 01) remains in `backlog/` **or** `active/` — only the `<epic-slug>-00-overview.md` index is left. If runnable SPECs remain, do nothing here and continue.
2. **Final epic review (against ALL requirements).** Re-read `<epic-slug>-00-overview.md` — its goal, the ordered SPEC list, dependencies, and cross-cutting notes — and verify the epic as a whole is actually delivered:
   - every `<epic-slug>-NN-*.md` it lists is in `done/` with `commit` + `files` filled in;
   - the overview's stated goal / acceptance / cross-cutting notes are met by the union of those shipped SPECs (not just each SPEC in isolation);
   - no requirement in the overview is silently unshipped or only partially done.
   Print a short epic-completion summary (goal + ✓/✗ per listed SPEC + per cross-cutting note). **A gap is a blocker:** if any requirement is unmet or any SPEC is missing from `done/`, surface it and do NOT close the epic — propose the follow-up SPEC (`--spec` / a new backlog file) instead.
3. **Close the epic (clean review only).** Move `<epic-slug>-00-overview.md` (and any other stray epic file) `backlog/ → done/`, set its `Status: done`, and note the completion date. After this, no file of a completed epic remains in `backlog/`.
4. **Offer a fresh Telegram build (only if configured).** After a clean close, run the Telegram delivery offer — see **Workflow: --deliver → "Offer after a ship"**: ask ONCE "Send the build to your Telegram now? (y/N)", and on `y` **assemble a fresh APK** that includes the epic's changes (`./gradlew :app:assembleDebug`, stop on build failure) and send it to Telegram. Skip silently when Telegram is not configured. Do this BEFORE the post-ship feedback question so the user can try the built app before rating it.

---
