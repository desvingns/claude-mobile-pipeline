<!-- mp-runtime-contract: post-ship -->

## Post-ship (after a ship): deliver → feedback → knowledge → nudges

After a successful `--feature` / `--bugfix` (post-docs), run these four closing moves in order.

**1. Telegram delivery (when configured, epic-scoped).** When Telegram delivery is configured, offer the build FIRST — before asking for feedback — so the user can try the built app before rating it. Run the **Offer after a ship** flow (see **Workflow: --deliver → Offer after a ship**) now: offer ONCE in {{UI_LANGUAGE}} “Send the build to your Telegram now? (y/N)”, and on `y` assemble a fresh artifact and send it. Skip silently when Telegram is not configured.

**2. Feedback — one question, per epic (not per SPEC).** Ask exactly ONE question (Claude →
`AskUserQuestion`; Codex → in chat), in {{UI_LANGUAGE}}: "Does the result match what you wanted?
5 — perfect / 4 — minor nits / 3 — partly / 2 — wrong direction / 1 — not at all (add a short
note if <5)".

**Epic-scoped timing.** When the shipped SPEC belongs to a multi-SPEC epic — its filename is
`<epic-slug>-NN-<short>.md` and an `<epic-slug>-00-overview.md` index exists — ask the feedback
question ONLY when this ship **completes the epic**: i.e. no other SPEC of the same `<epic-slug>`
remains in `.claude/specs/backlog/` or `.claude/specs/active/` (the just-shipped one is already in
`done/`). While earlier SPECs of the same epic ship, **skip the question silently** (it is asked
once, at the end, so the user reviews the whole epic together — not after every slice). A
standalone SPEC (no `<epic-slug>-NN` pattern / no epic overview) is its own "epic" → ask
immediately, as before. `--bugfix` and free-text `--feature <desc>` are always standalone → ask
immediately.

Then record it (see **Run telemetry**):
`--agent feedback --verdict <pass for 5-4 | partial for 3 | fail for 2-1> --metric "score=<N>" --note "<user note>"`.
If the score is ≤3 → also append ONE bullet to `selfimprove/lessons.md` at the repo root
(create the file with a `# Lessons` header if missing, never rewrite existing lines):
`- <YYYY-MM-DD> <task slug>: feedback <N>/5 — <user note / what missed>`.
If the note states a durable cross-project preference ("always…", "I never want…", a taste
statement not specific to this app), flag it in SESSION_RECAP as a `user_preference` candidate —
`{{PREFIX}}-knowledge` routes it through `{{PREFIX}}-brain-memory.sh append-candidate` to the
human-gated brain inbox; neither agent writes the curated cross-project profile/core directly.
Skip the question only when the user is explicitly rushing, or when the shipped SPEC is a
non-final slice of its epic (per Epic-scoped timing above) — never skip silently for any other
reason.

**3. Knowledge capture (optional, conservative).** You MAY spawn `{{PREFIX}}-knowledge` with
`{SPEC, CHANGED_FILES, SESSION_RECAP}` — SESSION_RECAP MUST include the feedback score + note
when collected (a low score is the strongest signal a lesson exists). No-op for routine work.
It routes lessons:
- **PROJECT-LOCAL** → writes this project's memory / `.claude/mp/extras/<agent>.md`.
- **PLUGIN-LEVEL** → returns `plugin_improvements[]`; for each, spawn `{{PREFIX}}-improve` to STAGE it
  to the queue (`mobile-pipeline/.ai/proposals/`) — do NOT open a PR per lesson.
Skip entirely when the task was trivial.

**4. Improvement-queue + retro nudges (cheap, silent checks).**
- Resolve `mp_repo` (as in `--improve`; skip silently if unresolved). Count
  `mp_repo/.ai/proposals/*.patch`: if ≥3 → tell the user
  "N pipeline improvement proposal(s) are queued — run `/{{PREFIX}} --improve --drain` to open the batch PR."
- If any telemetry call this session returned `"retro_due":true` → offer the retro once
  (see **Run telemetry**).

### `--feature --next --chain` (Codex only)

This modifier authorizes one fresh Codex task after the current backlog SPEC has **successfully**
moved `active/ → done/`. It is a conveyor, not a bypass: run every applicable epic-completion and
post-ship step above first. If any check failed, a human gate is still awaiting an answer, the epic
review found a gap, or the current SPEC was not moved to `done/`, do **not** create a task.

Before hand-off, inspect `.claude/specs/`: ignore `*-00-overview.md` files and create a successor
only when at least one runnable SPEC remains in `backlog/`. If none remains, report that the chain
completed normally and create no empty task. The next invocation still uses `--next`, so its standard
rule remains authoritative: if an active SPEC exists when it starts, it resumes that SPEC; otherwise
it takes the first ordered backlog SPEC.

<!-- tool:codex -->
1. Confirm `git branch --show-current` returns `main`. If it does not, stop and report the actual
   branch; do not switch branches and do not schedule a task from an unexpected checkout.
2. Fork the current Codex task with `fork_thread` and
   `environment: { type: "same-directory" }`. This makes a new local task on the same checkout
   without a worktree or Git branch, retaining this task's selected model and reasoning effort.
3. When the fork returns its task id, send that task exactly this user-visible follow-up prompt:
   `Run $mp --feature --next --chain now. Work directly in the current main checkout; do not create a worktree or Git branch. If no active or runnable backlog SPEC remains, report the drained board and stop.`
4. If forking or sending the prompt fails, report the failure and do not retry by creating another
   task. The completed SPEC stays durable on the board, so the user can safely start
   `$mp --feature --next --chain` manually.
<!-- /tool:codex -->

<!-- tool:claude -->
Codex task creation is unavailable in Claude. After a successful close, report the next command
`/{{PREFIX}} --feature --next --chain` and stop; never emulate it by spawning an implementation
agent in the current session.
<!-- /tool:claude -->

---
