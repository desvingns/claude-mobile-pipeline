<!-- mp-runtime-mode: feature -->
<!-- mp-runtime-contracts: startup execution platform device telemetry risk-routing feature-implementation backlog post-ship rules rules-board rules-implementation rules-learning -->

## Workflow: --feature

**Mode select (read first).** If `--feature` carries `--next` or `--backlog <slug>` (or has no description while `.claude/specs/active/` holds a SPEC) → this is **backlog-consume mode**: the SPEC already exists and was approved when it entered the backlog, so SKIP Phase 0 + Phase 1 (no brainstorm, no questions, no SPEC re-draft, no approval gate) and jump to Phase 2:

1. Resolve the file — `--backlog <slug>` → the `.claude/specs/backlog/` file whose name matches `<slug>`; `--next` (or bare `--feature` with no description) → resume the SPEC already in `.claude/specs/active/` if one exists, else the top-ordered runnable file in `backlog/` (lowest `NN`; ignore `*-00-overview.md` index files).
2. **Staleness pre-check (cheap, before promoting).** A backlog SPEC can be drafted well before it is consumed, and the codebase may have moved on — a prior epic/review pass, or an adjacent SPEC, can leave this one fully or partially built already. Before moving the file, do a cheap grep/explore pass for the SPEC's target symbols/screens (the `CHANGED_HINT` entries + key `WHAT` behaviour terms) against current code:
   - **Substantially already exists** → do NOT silently spawn Phase 2. Surface the finding (what exists + where) and offer "Close as already delivered? (y/N)" — on `y`, skip Phase 2, move the file straight `backlog/ → done/`, fill `Implementation links` from the evidence found, set `Status: done`, and run **Epic completion** if this closes the epic; on `N`, proceed to Phase 2 as written.
   - **Partially exists** → surface the gap (built vs. still-needed) and offer "Re-scope the SPEC to the remaining gap before implementing? (y/N)" — on `y`, tighten `WHAT`/`CONSTRAINTS` to the actual remaining gap (still the same approved file, no new gate) before Phase 2; on `N`, proceed with the SPEC as written.
   - **No meaningful overlap found** → proceed silently to step 3. This check must stay cheap (a few targeted greps, not a full re-exploration) and must never block a genuinely-unstarted SPEC.
3. Move it `backlog/ → active/`, set front-matter `Status: active`, announce which SPEC, then run **Phase 2** using the `=== SPEC === … === END SPEC ===` block read verbatim from the file.

   **Carry the epic's design capsule into the SPEC.** If this SPEC belongs to an epic
   (`<epic-slug>-NN-<short>.md`), read the `## Design capsule` section of its
   `<epic-slug>-00-overview.md` (in `backlog/` or `done/`) and append it verbatim to the SPEC block
   under a `DESIGN_CAPSULE:` line before passing it to any Phase 2 agent. This mode skips Phase 0
   and Phase 1, so the capsule is the **only** design input the developer gets: state ownership,
   forbidden dependency edges, lifecycle call sites, ordering, the timeout budget, and the test-clock
   model. Without it those decisions get made inside the implementation and then found one at a time
   by semantic review, after the code exists. Costs no extra agent call — the planner already wrote it.

   If the epic has no overview, or the overview has no capsule, say so in one line and continue —
   an older epic predates the section. Do not spawn an agent to reconstruct it here; that belongs to
   the escalation path in `contract-risk-routing.md`.

   **Presentation SPECs — announce intent, do not re-gate.** When `SPEC.LAYERS` contains
   `presentation`, the announcement carries two extra sentences before Phase 2 starts: the visual
   result you expect to produce, in plain language, and what you are treating as the target of
   comparison (a reference image for a clone; otherwise the specific described behaviour or the
   existing screen you are changing). This is **informational** — keep running; it is NOT a second
   approval gate, and asking for one here would contradict the backlog-consume authorization. Its
   only job is to surface a misread target in one line the user can interrupt, instead of after a
   full build. Post-ship feedback shows misread visual intent is a top rework cause, and this mode
   skips the Phase 1 echo-back that would otherwise have caught it. It applies to every project,
   clone or not — a greenfield screen can be misread just as easily.
4. On ship (Verifier pass / push), move it `active/ → done/`, fill `Implementation links` (commit + files), set `Status: done`. Then run the **Epic completion (final review + close)** check (see **SPEC backlog board**): if this was the epic's last SPEC, review the epic against ALL requirements in its `-00-overview.md` and, on a clean review, move that index `backlog/ → done/` too.

If a free-text description was given instead → run Phase 0 → Phase 1 → Phase 2 as normal.

### Phase 0 — Brainstorm trigger (optional)

Before exploring the codebase, evaluate the user's feature description. Trigger heuristics:

- Description longer than ~150 characters, OR
- Touches ≥2 architectural layers (e.g. "new screen + new entity" → presentation + domain + data), OR
- User signals uncertainty ("thinking about", "not sure", "what's better", "options for", "how do I")

  (or equivalent phrases in the project's configured UI language)


If any trigger fires → ask:
"This looks like a large feature. Run brainstorm before SPEC? (y/N)"

If **y** → spawn `mp-architect` (same prompt as `--discuss` Phase 1), show the BRAINSTORM block, then ask:
"Which option do we take? (1 / 2 / 3 / cancel)"

- If user picks a number → proceed to Phase 1. Include the choice in `WHAT` or `CONSTRAINTS` of the SPEC so the developer knows which option was chosen.
- If user says "cancel" → stop. Do not generate a SPEC.

If no trigger fires, or user answers **N** → proceed directly to Phase 1.

### Phase 1 — Spec (grill-first elicitation)

Explore the relevant codebase area. Then **grill the feature into a tree of decisions** before emitting any SPEC — do not jump straight to a flat question list, and do **not** cap the number of questions.

**Grill protocol (always run; ambiguity-scaled).**
1. From the feature description + what the exploration found, sketch (internally) the **decision tree**: the small set of choices that, once made, determine everything downstream. Roots first — which screen/flow, new screen vs. extension, the single core behaviour, what is explicitly **out of scope** — then the branches each root opens: new-vs-existing use case, persistence (Room entity / DataStore key / Core Data entity / …), validation rules, empty/loading/error states, integrations.
2. **Rank the open decisions by leverage** (how much downstream each one determines). Enumerate them internally before asking anything.
3. Ask **one decision at a time** (a tight 2–3 sub-choice cluster of the *same* parent may share one call), resolving a **parent before its children**. Always offer a **recommended answer** drawn from the codebase/exploration **and the cross-project user profile** (Startup step 3) — when a profile fact informs the recommendation, say so in a short parenthetical (e.g. "recommended: dark theme — your usual choice across projects"); the profile biases recommendations, it never decides. Mark the recommended option as such (in the project's configured UI language), so the user can accept with one tap or correct you. **Re-plan the tree from each answer before the next question.**
4. Be a skeptic, not a stenographer. On every answer hunt for a hidden **assumption**, a **contradiction** with an earlier answer, an unhandled **state** (empty / loading / error / offline / first-run / unauthenticated), **scope creep** (a sub-feature with no traceable root in the core behaviour), or a **new dependency** the answer just created. A found hole becomes the next question — follow that branch before returning to breadth.
5. **Budget scales with ambiguity — there is NO fixed question cap.** A trivial change (e.g. "new button → navigate to X") surfaces ~0 high-leverage unknowns → ask nothing (or a single confirm) and proceed straight to the SPEC. A genuinely tangled feature may need many. **Stop** when all root/high-leverage decisions are settled and no open branch has an unresolved hole, OR the user says "enough / proceed" (log remaining items as `(assumption)` with your recommended defaults), with a **hard ceiling of ≤12** as a backstop, not a target.

**Harness note.** Ask via the harness's question mechanism: Claude → `AskUserQuestion`, one decision per call, the recommended option **first**; Codex → ask the one question in chat and **STOP** until the user replies (state the recommended answer in the text). Never batch the tree; never proceed on an unanswered question.

Carry the resolved decisions into the SPEC: every `WHAT` / `CONSTRAINTS` line must trace to a grilled decision, the exploration, or an explicit `(assumption)`; never put an "out of scope" item into the SPEC.

When the decisions are settled, output — at the SAME approval gate, in this order:

1. **Intent echo-back** (2–3 sentences, in the project's configured UI language, titled "Как я понял задачу" or the
   equivalent): a plain-language reconstruction of what the user actually WANTS — the goal, the
   one behaviour that must become true, and what is explicitly out of scope. This is NOT a
   paraphrase of the SPEC fields — it is your understanding of the intent, so a misread idea is
   caught here, before any code. If the user corrects the echo-back, re-plan (and re-grill the
   affected branch) before re-emitting.
2. The SPEC block:

```
=== SPEC ===
TASK: feature
PLATFORM: [android | ios — only required when project has multiple platforms]
WHAT: [one sentence]
LAYERS: [domain] [data] [presentation]
CHANGED_HINT: [existing files to read, or "explore"]
TEST_TYPES: unit [dao] [compose-ui] [screenshot]
CONSTRAINTS: [specific rules or "none"]
```

**Large features → split into a SPEC backlog.** Before emitting a single SPEC, judge the size. If the feature naturally decomposes into **two or more** independently-shippable SPECs (each roughly one focused slice — one screen group, one design layer, one subsystem), do NOT cram it into one. Instead:

1. Draft the full ordered set (SPEC 1..N), each its own self-contained SPEC block.
2. Write each as a file in `.claude/specs/backlog/` — see **SPEC backlog board** below for layout + file format — behind ONE y/N gate: *"Write N SPECs to backlog? (y/N)"*. Add an `<epic-slug>-00-overview.md` index listing the ordered SPECs, their dependencies, and any cross-cutting notes.
3. Promote the first SPEC: move its file `backlog/ → active/`, then continue Phase 2 on it.
4. The remaining SPECs stay in `backlog/` for the next `/mp --feature` run (the top-ordered one is next).

A single-SPEC feature skips the board — emit the SPEC inline as before.

**Do not proceed until user confirms SPEC.**


> Phase 2 is defined in required contract `contract-feature-implementation.md`; execute it here, before Phase 3.

### Phase 3 — Report

```
feat: [description]
   Commit: [hash]
   Tests: [N passed]
   Lint:  ok
   Pushed: yes / failed: [reason]
   Files: [list of created/changed files]
```

---
