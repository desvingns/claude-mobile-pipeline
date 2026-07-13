# Handoff

UPDATED: 2026-07-10 by codex

## LATEST (2026-07-10, codex) — GPT-5.6 model-tier refresh
- **DONE:** upgraded active high-capability MP Spec roles (evaluator, screenshot analyzers, fit checklist author, crawl executor/reviewer) and MP Dev developer/fit tiers from `gpt-5.5` to `gpt-5.6`; preserved the existing reasoning effort and sandbox configuration. Updated the canonical installer/templates, generated marketplace copies, and MyMoney's default model plus its five pinned native agents.
- **VERIFIED:** official OpenAI model documentation reports GPT-5.6 preview availability; shell syntax, marketplace dry-run, all 37 MyMoney TOML files, active-reference scans, and diff checks pass. `graphify update .` completed AST extraction but correctly refused to replace the existing 4,625-node graph with the smaller 4,615-node result.
- **NEXT:** rebuild/reinstall the marketplace when publishing the next pipeline release so other downstream projects receive the new defaults.
- **OWNER:** codex. **BLOCKERS:** GPT-5.6 remains preview-gated to eligible accounts.


UPDATED: 2026-06-17 by claude

## LATEST (2026-06-17, claude) — Telegram build delivery (`/{{PREFIX}} --deliver`, v1.9.0)
- **DONE:** new deterministic step to self-deliver a built artifact over Telegram via an MTProto
  **user** session (Telethon) — default target `me` (Saved Messages), 2 GB cap (no bot API 50 MB
  limit, no local Bot API server). NEW `templates/common/scripts/{{PREFIX}}-deliver-telegram.sh`:
  cross-platform bash wrapper, MTProto call delegated to `python3` + `telethon` (external dep like
  adb/gradle); reads `TG_API_ID`/`TG_API_HASH`/`TG_SESSION`/`TG_TARGET` from env or a gitignored
  repo-root `.env` (TG_* keys parsed, never executed); auto-detects newest `*.apk` under
  `*/build/outputs/*`; `--login` mints a StringSession; emits one JSON line, mirrors `ok`→exit.
  Wired into the orchestrator (Usage, Deterministic-steps, **Workflow: --deliver** with one-time
  setup + optional post-build send offer). NEW `docs/TELEGRAM-DELIVERY.md`.
- **VERIFIED:** `bash -n` (template + generated) clean; `lib/build-marketplace.sh` ships it as
  `claude-plugins/mp-dev/scripts/mp-deliver-telegram.sh` (auto-picked by the common-scripts loop),
  0 `{{…}}`/marker leaks, `${CLAUDE_PLUGIN_ROOT}` rewrite correct; all plugin manifests + marketplace
  now `1.9.0`; `graphify update .` ok. shellcheck not installed locally → CI remains the authority.
  **NOT run end-to-end** (needs real `api_id`/`api_hash` + a phone login to mint a session).
- **NEXT:** user does the one-time `--login` to mint `TG_SESSION`, drops the TG_* secrets in a
  gitignored `.env`, then `/{{PREFIX}} --deliver` (or direct script) to confirm a real send. NOT
  committed. **[codex] FYI:** `affects: claude, codex` log entry `2026-06-17T12:00-telegram-build-delivery`
  — pick it up on next sync (no codex-owned file changed; common-scripts loop already ships it).
- **OWNER:** claude. **BLOCKERS:** none.

---

UPDATED: 2026-06-11 by codex

## LATEST (2026-06-11, codex) — publish plugin release metadata for 1.7.0
- **DONE:** released the previously-authored `[Unreleased]` batch as `1.7.0` in `CHANGELOG.md`,
  bumped root `VERSION` to `1.7.0`, and synced all Claude/Codex plugin manifests plus the Claude
  marketplace metadata to `1.7.0`.
- **DONE:** hardened `lib/build-marketplace.sh` so future marketplace builds read root `VERSION` and
  rewrite the manifest `version` fields for `.claude-plugin/marketplace.json`, both Claude plugin
  manifests, both Codex plugin manifests, and the Codex mp-dev template manifest.
- **VERIFIED:** `lib/build-marketplace.sh` full run + dry-run; manifest JSON parse; `bash -n
  lib/build-marketplace.sh`; placeholder/tool-marker leak greps; `git diff --check`; `graphify update .`.
  Local `shellcheck` is not installed, so CI remains the shellcheck authority.
- **NEXT:** downstream projects should run their plugin marketplace update/install flow and see
  `mp-dev` / `mp-spec` as `1.7.0`.
- **OWNER:** codex. **BLOCKERS:** none.

UPDATED: 2026-06-11 by claude

## LATEST (2026-06-11, claude) — pipeline audit → 46-item roadmap, ALL 6 STAGES AUTHORED
- **DONE (stage 6, claude-011 — D1 D2 D3 D4+D7 D5 D9):** fidelity instrumentation. NEW
  `bounds-to-dp.sh` (exact dp into element manifests; checklists quote numbers) + NEW
  `{{PREFIX}}-pixel-diff.sh` (ImageMagick RMSE→similarity + heatmaps; `--fit` Phase 2.5
  objective pixel pass; agent anchors `fit_score` to it). Demo-mode capture normalization on
  BOTH sides (crawl + `--fit`), AVD profile/density recorded. `apk-analyzer` Pass 7.5 extracts
  fonts/icon/drawables → `spec/assets/` (+ legal caveat). Phase D emits
  `spec/design-tokens.json` → project `.claude/mp/design-tokens.json` → ui-designer generates
  Color.kt/Type.kt directly (Theme Builder = greenfield fallback only). Fit agent walks every
  checklist row → `checklist_rows[]` verdicts. Both scripts fixture-tested; plugins
  regenerated, 0 leaks. Change-log: `2026-06-11T10:30-clone-fidelity-instrumentation`. STATUS:
  authored; **NOT committed**. Task: `.ai/tasks/claude-011-clone-fidelity.md`.
- **DONE (stage 5, claude-010 — C1 C2 C3 C5 C6 C7 authored; C10 pending):** three deterministic
  clone-completeness gates. NEW `scripts/crawl/element-manifest.sh` (ST*.xml → per-state
  interactive-element JSON; fixture-tested) wired into A.0 finalize; `fit-checklist-author`
  merges them into `spec/fit/elements/<Sxx>.json`; `spec-evaluator` rubric v1.1.0 gains
  **Class 5 affordance coverage** (unmatched element = blocker) + **clone-strict**
  (orphan/state-gap → blocker); GATE 2 prints all coverage-gap lists explicitly; `--plan
  --phases` gains a **plan-coverage audit** (registry screens + FR/US ids → ≥1 task, else
  blocked); `--fit` captures built ui-dumps and `{{PREFIX}}-fit-android` runs a **structural
  element diff** before the visual pass. Docs updated (REFERENCE-CRAWLER, CLONE-PLAYBOOK).
  Plugins regenerated, 0 leaks. Change-log: `2026-06-11T09:30-clone-completeness-gates`.
  **C10 (device run of crawl Phases 2–4 + these gates) still needs the throwaway-AVD session**
  (claude-004 NEXT). STATUS: authored; **NOT committed**. Task:
  `.ai/tasks/claude-010-clone-completeness.md`.
- **DONE (stage 4, claude-009 — A11 E5 A12):** CI propagation. NEW
  `.github/workflows/regen-plugins.yml` (push to main touching templates/** or the generator →
  auto-regen + commit the plugin trees; loop-guarded via paths filter; safety net — PRs stay
  gated by the drift check). `validate-plugins.yml` extended: bash -n over
  templates/selfimprove/eval/installers + NEW `shellcheck -S error` step (**watch the first CI
  run** — legacy scripts may surface error-level findings). A12: `selfimprove/README.md`
  "Scheduling the loop" (weekly host-side `/mp --reflect`, projects.txt upkeep) +
  docs/MARKETPLACE.md propagation chain. Change-log: `2026-06-11T08:30-ci-propagation`. STATUS:
  authored; **NOT committed**; workflows validate for real on first push. Task:
  `.ai/tasks/claude-009-ci-propagation.md`.
- **DONE (stage 3, claude-008 — A5 A6 A7 A8 E1):** conveyor continuity. Intent **echo-back**
  ahead of the SPEC at the same gate; new **`--continue`** workflow (read-only state inspection →
  ONE recommended next command behind y/N); **phase-exit hook** (auto `--check`, clone → `--fit`
  offer); **Stale-Test Update Rule** (orchestrator passes MODIFIED_EXISTING; tester reconciles
  old tests, returns `stale_tests_reviewed[]`; verifier **Check 6 `stale_tests`**, six-check
  pass logic); **`fitThreshold`** (config, default 85) now ENFORCED by `--fit` (PASS|FAIL +
  "clone not done" on FAIL). build-marketplace argument-hint gains `--continue`. Plugins
  regenerated, 0 leaks. Change-log: `2026-06-11T07:30-orchestrator-continuity`. STATUS:
  authored; **NOT committed**. Task: `.ai/tasks/claude-008-orchestrator-continuity.md`.
- **DONE (stage 2, claude-007 — B1 B2 B3 B4):** cross-project USER profile
  (`$MP_USER_PROFILE` / `~/.config/mobile-pipeline/user-profile.md`). `{{PREFIX}}-knowledge`
  gains the `user_preference` routing category + owns the skeleton/merge rules; `/mp` Startup +
  grill and `/mp-spec` grill (grill-me v1.2.0, neutral/marker-free) + greenfield stage defaults
  READ it (bias recommended answers only — never auto-decide, absence changes nothing);
  `{{PREFIX}}-fit-android` emits optional `taste_signals[]` (from INTENDED deviations only) that
  `--fit` records behind a y/N gate; post-ship feedback notes flag "always/never" statements as
  profile candidates. docs/ARCHITECTURE.md gains the profile layer. Plugins regenerated, 0
  leaks. Change-log: `2026-06-11T06:30-cross-project-user-profile`. STATUS: authored; **NOT
  committed**; not yet exercised live. Task: `.ai/tasks/claude-007-user-profile.md`.
Deep audit of the repo against the two user goals (closed dev loop; Play-Store clone with max
similarity), triggered by the last clone iteration's failures (design mismatch + forgotten
buttons). Then the user said "start implementing" → **stage 1 (claude-006) is authored + validated
in the same session.**
- **DONE (stage 1, claude-006 — A1 A2 A3 A4 E8):** the self-improvement loop now feeds itself.
  NEW pipeline scripts `templates/common/scripts/{{PREFIX}}-record-run.sh` (L1 capture → one JSON
  event per step into `<repo>/selfimprove/runs/`, `--tokens-in/--tokens-out/--cost` fields,
  `retro_due` after ≥`$REFLECT_AFTER` (10) unreflected events) and `{{PREFIX}}-retro.sh` (L2
  per-project retro: pass-rate, feedback scores, token totals, failure tail). Orchestrator:
  new "Run telemetry (fire-and-forget)" section + record points (reviewer / final-runner /
  verifier / fit), retro offer on `retro_due`, and "Knowledge capture" expanded into
  "Post-ship: feedback → knowledge → nudges" (ONE mandatory score-1–5 feedback question →
  `agent=feedback` event; ≤3 → bullet in `selfimprove/lessons.md` + into SESSION_RECAP; drain
  nudge at ≥3 queued proposals). `{{PREFIX}}-knowledge` contract reads the score. Root
  `selfimprove/` kit parity-updated. Scripts `bash -n` clean + functionally tested in a temp
  root (threshold fires at 11, counter resets after retro, error paths emit `ok:false` exit 0);
  **plugins regenerated, 0 leaks** (new `mp-record-run.sh`/`mp-retro.sh` shipped). Change-log:
  `2026-06-11T05:30-loop-telemetry-feedback`. STATUS: authored + validated; **NOT committed**;
  not yet observed in a live `/mp` session. Task: `.ai/tasks/claude-006-loop-telemetry.md`.
- **DONE:** `docs/IMPROVEMENT-ROADMAP.md` — canonical catalog of **46 improvements** (A loop /
  B user-memory / C clone-completeness / D design-fidelity / E infra) with evidence pointers
  into `templates/`, staged into 6 queued task briefs **`.ai/tasks/claude-006…011`**
  (loop-telemetry, user-profile, orchestrator-continuity, ci-propagation, clone-completeness,
  clone-fidelity). CHANGELOG `[Unreleased]` noted. Plan:
  `C:\Users\k.shavrin\.claude\plans\generic-jumping-flame.md` (user-approved).
- **DECISIONS (with user):** loop-first priority — stages 1–4 (telemetry/auto-reflection,
  user profile, echo-back + `--continue` + stale-test rule, CI auto-regen) before clone stages
  5–6. Approved new tooling: ImageMagick/SSIM pixel diff, apktool/aapt2 asset extraction,
  GitHub Actions, scheduled auto-runs.
- **KEY FINDINGS:** learning loop only ~30 % closed (`selfimprove/record-run.sh` never invoked;
  reflect/drain are manual flags; **no cross-project USER memory**; tester never updates stale
  tests of changed behaviour). Clone: **5 non-blocking loss points** let visible affordances
  vanish (planners never audit FR/screen/registry→task coverage; `coverage_gaps[]` never
  surfaced; orphan/state findings warn-only). Fidelity: crawl ui-dump pixel bounds unused, no
  asset extraction, manual Theme Builder seam, `--fit` has no pixel diff / enforced threshold /
  capture normalization; crawl Phases 2–4 still not device-proven (see claude-004).
- **NEXT:** 1) user go-ahead → commit ALL six stages + the roadmap artifacts (one commit per
  stage or one batch — user's call); 2) live validation pass: one `/mp --feature` run on a
  wired project (006/007/008), first CI push (009 — watch the new shellcheck step), and the
  C10 throwaway-AVD clone run exercising the completeness + fidelity gates (010/011,
  claude-004 NEXT); 3) backlog items (16) stay in `docs/IMPROVEMENT-ROADMAP.md` for later
  promotion.
- **OWNER:** claude (stages 1–6). **[codex] FYI:** stage 4 will add CI that auto-regenerates
  plugin trees on main — pull before regenerating locally; `lib/sync.sh` remains codex-001.
- **BLOCKERS:** none.

## LATEST (2026-06-05, claude) — grill-me design-tree interrogation in /mp-spec intake
User asked to add Matt Pocock's **grill-me** skill to complement spec creation. Ported it as a
**reusable orchestrator technique** (NOT an agent), wired into both intake modes.
- **Decided with user:** scope = **both modes**; activation = **always in greenfield** (escape
  hatch `--no-grill`).
- NEW `templates/spec/skills/app-spec-creator/prompts/techniques/grill-me.md` (id
  `techniques/grill-me`, v1.0.0, neutral) — design-tree rule (roots before branches),
  ask-one-at-a-time funnel, recommended-answer convention, adversarial hole-poking
  (assumptions/contradictions/unhandled states/scope creep), stop conditions/budgets, decisions
  ledger output. **Marker-free on purpose:** prompt-library files are copied raw (only SKILL.md is
  rendered) — I first authored it with `tool:` blocks, the leak check caught them in the generated
  plugin, rewrote the harness note as neutral prose. grill-me was the only prompt that ever used
  markers; convention is now confirmed clean.
- `SKILL.md`: `--no-grill` flag; A-green **Stage 0 grill** (mandatory, after the idea paragraph,
  writes `input/interview/grill.md`); A-clone grills `ambiguities[]`/`state_gaps[]`
  (dependency-ordered, one at a time → `pipeline/grill.md`) replacing the flat dynamic batch B when
  ambiguities exist; GATE 1 reconciles against the ledger; two bundle-layout slots added.
  `greenfield.stage1-vision.md` runs the grill after capturing the idea. `prompts/README.md` +
  `docs/SPEC-PIPELINE.md` updated.
- No new agent ⇒ no `install-spec.sh` / `openai.yaml` / AGENTS-roster change (both installers copy
  `prompts/` raw, so it propagates). Regenerated **both** plugin trees (`lib/build-marketplace.sh`);
  **0 leaks** in the new prompt + SKILL + stage1 across claude & codex.
- CHANGELOG `[Unreleased]` + change-log `2026-06-05T10:30-grill-me-design-tree` (affects claude,
  codex) + task `.ai/tasks/claude-005-grill-me.md`. VERSION left at 1.5.0 ([Unreleased] still open).
- STATUS: **authored + builds clean + 0-leak verified; NOT committed; not yet run end-to-end** in a
  live `/mp-spec --greenfield` session. NEXT: run one greenfield session to validate the grill UX,
  then commit. [codex] pick up the log entry on next sync (no codex-owned file changed).

## LATEST (2026-06-03, claude) — full `fidelity` → `fit` concept rename + flag `--crawl` → `--graph`
Two user-requested renames, then pushed to main.
- **`--crawl`/`--no-crawl` → `--graph`/`--no-graph`** (the dynamic-crawl flag) across live artifacts +
  regenerated plugins. Committed + pushed earlier as `8b8a6ba`.
- **`fidelity` concept → `fit` repo-wide** (completing the 1.5.0 flag-only rename). `git mv`:
  `fidelity-checklist-author`→`fit-checklist-author`, `{{PREFIX}}-fidelity-android`→`{{PREFIX}}-fit-android`,
  `eval/clone-fidelity`→`eval/clone-fit`, + generated `mp-fidelity-android`→`mp-fit-android`. Content
  tokens: `spec/fidelity`→`spec/fit`, `build/fidelity`→`build/fit`, `fidelity_score`→`fit_score`,
  Fidelity-gate→Fit-gate, `=== FIDELITY ===`→`=== FIT ===`. install-spec AGENTS row updated; plugins
  regenerated. **Released CHANGELOG [1.5.0] + the append-only change-log's prior entries keep "fidelity"
  verbatim** (history); `graphify-out/*` is generated (refreshes on the graphify hook). Change-log:
  `2026-06-03T19:00-rename-fidelity-concept-to-fit`.
- **Breaking for downstream:** projects referencing `mp-fidelity-android` / `fidelity-checklist-author`
  or `spec/fidelity/` paths must update (MyMoney_app, diet_helper — not touched here).
- Crawler itself remains feature-complete (Phases 1–4); full loop still not run end-to-end on a device.

## LATEST (2026-06-03, claude) — reference-APK crawler, Phase 4 (closes the clone loop) — FEATURE-COMPLETE
`fidelity-checklist-author` now consumes the crawl's observed per-state frames (`crawl_graph` +
`crawl_states_dir`): per-screen must-match grounded in the real **empty AND filled** states (the
`data_state:"filled"` ones seeding produced), a visual block per state, and a `registry.csv` row per
(screen, state) with a `data_state` column — so `--fit` drives the built app into each state and
compares it to its own reference frame (kills the empty-state divergence class). SKILL Step 7 passes the
crawl inputs to the fidelity author when A.0 ran. Docs: `CLONE-PLAYBOOK.md` gains a Step 0 (crawl
front-door) + updated loop diagram; new `docs/REFERENCE-CRAWLER.md` consolidates the subsystem. Auto-
enable on `--depth reference` was already wired (Phase 1). No new agents/scripts; plugins regenerated,
0 leaks. Change-log: `2026-06-03T18:00-reference-crawler-phase4`.

**Crawler is now feature-complete across all 4 phases** (primitives → trio+coverage → seeding/auth →
fidelity). Phase 1 was device-validated (3 bugs fixed); Phases 2–4 are authored + build/lint/0-leak
clean but the **full loop has not been run end-to-end on a device**. NOT committed (codex mp-dev-bridge
WIP also sits in the tree). NEXT: a throwaway-AVD end-to-end run (crawl → spec → build → `--fit`) on a
clonable app — expect replay/seeding rough edges to surface, as Phase 1 did. Task: `.ai/tasks/claude-004-reference-crawler.md`.

## LATEST (2026-06-03, claude) — reference-APK crawler, Phase 3 (autonomous seeding + auth)
The crawl now observes **populated** states, not just empties. `crawl-navigator` emits `auth` goals
(get past a sign-in/onboarding wall — unblock before breadth) and `seed` goals (create entries to reveal
an empty state's filled form), plus `explore`. `crawl-executor` branches on `goal.type`: auth =
fill+submit the form (user `credentials` if provided, else self-register with synthetic data; detect
OTP/captcha verification walls); seed = open the create flow and create `count` synthetic entries, then
capture the `data_state:"filled"` result. Added a deterministic ASCII synthetic-data fixture set
(reproducible corpus) + hardened guardrails (synthetic only; no real-money/send/share; verification wall
→ `blocker:needs_human`, accept-and-prune). `crawl-reviewer` judges auth/seed success from the
after-shot. `clone.crawl-setup` gains consent modes (seed | explore-only | decline) + an optional
**test-credentials** question — **credentials are runtime-only and MUST NOT be written to meta/trace/
session/bundle/any committed file** (the orchestrator holds them in-session and passes them to the
executor for auth goals). No new agents/scripts; plugins regenerated, 0 leaks. Change-log:
`2026-06-03T17:00-reference-crawler-phase3`. STATUS: **authored + builds/lints clean; auth/seed not yet
run on a device.** NEXT: validate auth + a create flow on a throwaway AVD (confirm a filled node +
creds never hit artifacts), then Phase 4 (feed `fidelity-checklist-author` the real per-state frames).
Not committed.

## LATEST (2026-06-03, claude) — reference-APK crawler, Phase 2 (agent trio)
Split the single-agent crawler into a **separate-session trio** + an orchestrator-owned, file-persisted
loop. New `crawl-navigator` (sonnet, read-only — picks the next affordance + replay path, decides done)
and `crawl-reviewer` (opus multimodal, read-only — classifies the edge flow/cycle/error/dead_end, judges
the success_test, scores coverage_confidence, gates accept/continue). `crawl-executor` refactored
whole-crawl → **goal-scoped** (relaunch → replay path → one affordance → capture+dedup → return).
`SKILL.md` Step 2.0 is now the loop `navigator → (executor⇄reviewer, ≤2 retries) → merge → coverage`,
stop on done/plateau(K=4)/budget(40/25/60); finalize records `screenshot_file` per node.
`navigation-flow-analyzer` consumes the optional `state-graph.json` → `source:observed` edges override
guesses (crawl `ST*`→business `S*` mapped via the shared screenshot filename). `install-spec.sh` gains
crawl-navigator (gpt-5.4/medium) + crawl-reviewer (gpt-5.5/high). Plugins regenerated; `bash -n` clean,
dry-run roster shows all 3 crawl agents, 0 leaks. Change-log: `2026-06-03T16:00-reference-crawler-phase2`.
STATUS: **authored + builds/lints clean; trio loop not yet run end-to-end on a device.** NEXT: validate
the loop on a throwaway AVD with a real reference APK (NOT the user's live MyMoney emulator), then Phase 3
(autonomous seeding). Not committed.

## LATEST (2026-06-03, claude) — reference-APK crawler, Phase 1
Started **claude-004** (dynamic reference-APK crawler for `/mp-spec` clone intake). Approved plan:
`C:\Users\k.shavrin\.claude\plans\ai-steady-galaxy.md`. Brief: `.ai/tasks/claude-004-reference-crawler.md`.
STATUS: **Phase 1 authored, builds/lints clean, AND device-validated on a real emulator (3 bugs fixed). Not committed.**

DONE (this session):
- Device primitives `templates/spec/skills/app-spec-creator/scripts/crawl/`:
  `_crawl-lib.sh` + `device-preflight.sh` `app-control.sh` `screencap.sh` `ui-dump.sh` `input.sh`
  (cross-platform bash, one JSON line each, `$ANDROID_SERIAL`-targeted, mirror `mp-runner-android.sh`).
  `bash -n` clean (shellcheck not installed locally — CI/`validate-plugins.yml` should run it).
- `templates/spec/agents/crawl-executor.md` (opus): vision-first BFS, state dedup, forbidden-action
  guardrail, writes `trace.jsonl` + `state-graph.json` + fills `input/screenshots/`.
- `SKILL.md`: `--graph`/`--no-graph` (Step 0), new **Step 2.0 A.0-crawl**, `input/crawl/` bundle slot,
  observed-evidence note in A-clone. New prompt `prompts/questions/clone.crawl-setup.md`.
- Shipping: `install-spec.sh` AGENTS table gains `crawl-executor` (gpt-5.5/high) + both installers copy
  `scripts/`; `lib/build-marketplace.sh` copies `scripts/` into the mp-spec skill.
- **Regenerated the plugin trees** (`bash lib/build-marketplace.sh`): `claude-plugins/mp-spec` now
  carries `agents/crawl-executor.md` + `skills/mp-spec/scripts/crawl/*`; codex mp-spec gets the scripts.
  Verified: 0 `{{…}}`/tool-marker leaks in rendered `crawl-executor.md`; dry-run + `bash -n` clean.
- **Device-validated on a real emulator** (emulator-5554, Android 34): preflight/current/screencap/
  ui-dump/input(key,swipe,tap-xy,**tap-by-text**) all return valid JSON; `tap --text "Chrome"` →
  foreground became Chrome (full hybrid path proven on hardware). Fixed 3 bugs `bash -n` could not catch
  (`2026-06-03T15:00-reference-crawler-device-fixes`): MSYS `/sdcard` path mangling (Git Bash) in
  ui-dump → `MSYS_NO_PATHCONV` + `exec-out cat` redirect; `--clickable` too strict for Compose (label on
  a non-clickable node) → prefer-then-fallback; `launch` now confirms foreground + retries. Re-ran the
  plugin regen so the shipped scripts include the fixes. NOTE: the emulator is the user's **live MyMoney
  dev device** — MyMoney got uninstalled mid-test by their parallel work; coordinate before
  installing/clearing apps on it.

DECISIONS (+ why):
- Crawler is **additive** and lives in `/mp-spec` clone intake (Phase A.0) — it fills the existing
  `input/screenshots/` slot + one `state-graph.json`, so analyzers change only by an *optional* input
  later. See `.ai/memory/reference-crawler.md`.
- Orchestrator passes `scripts_dir` to the executor at runtime → scripts stay path-neutral (no
  plugin-vs-global hard-coding in the agent). Full autonomy ⇒ guardrails + graceful degradation.

NEXT / FOLLOW-UPS:
1. **Device smoke** (user has an emulator from `--fit`): preflight→install→screencap→ui-dump→input tap;
   each must print one valid JSON line. Then a real `/mp-spec --apk … --graph` A/B vs static.
2. Phase 2 (navigator/executor/reviewer trio + coverage gate + wire observed edges into
   `navigation-flow-analyzer`), Phase 3 (autonomous seeding), Phase 4 (fidelity frames). See task file.
3. **[codex]** for codex-side crawling parity, add `crawl-executor` to
   `templates/spec/codex/skills/app-spec-creator/agents/openai.yaml` (codex-owned; I left it untouched).
   Run shellcheck on `scripts/crawl/*.sh`.

OWNERSHIP NOTE: I edited the shared `install-spec.sh` + `lib/build-marketplace.sh` additively (scripts
copy + one AGENTS row) on top of codex's in-flight mp-dev-bridge changes already in the working tree —
no codex content removed. Did NOT touch `lib/render.sh`, `lib/sync.sh`, `bootstrap.sh`, or `.codex/`.

BLOCKERS: none (Phase 1 is code-complete pending a device smoke test).

---

## LATEST (2026-06-03, codex) - Codex mp-dev marketplace bridge
Added the missing Codex side of `mp-dev`: `codex-plugins/mp-dev` now ships a `$mp`/`/mp` skill,
`agents/openai.yaml`, and `references/codex-agent-shims.md`. Added canonical source templates under
`templates/dev/codex/` (`.codex-plugin/plugin.json`, skill files, `agent.toml.tmpl`, and
`config-fragment.toml`), wired `lib/build-marketplace.sh` to regenerate the Codex plugin, and added
`mp-dev` to `.agents/plugins/marketplace.json`. Docs now say Codex receives both `mp-spec` and
`mp-dev` skills while native `.codex/agents/mp-*.toml` shims remain per-project. The dev-agent Codex
tier policy is now active guidance, including `mp-fidelity-android` as `gpt-5.5/high` read-only.
Follow-up is only installer automation for those shims via future `lib/sync.sh` or bootstrap/install
work.

## LATEST (2026-06-02, codex) — visual autotest device gate
Added the hard Android visual/device autotest pre-flight requested from the MyMoney incident:
canonical `/mp` command template now stops before implementation/test execution for explicitly visual
tasks (visual/layout/theme/animation/screenshot/fidelity/reference comparison/visual QA,
`instrumented-compose-ui`, `--device`, `--fit`, or visual device done-criteria) when no usable booted
device/emulator is connected. Runner/tester/verifier templates now state that JVM screenshots,
manual checklists, or "BUILD SUCCESSFUL" cannot substitute for connected-device visual evidence.
Regenerated `claude-plugins/mp-dev` from templates. CHANGELOG `[Unreleased]` and
`.ai/changes/agent-skill-log.md` entry `2026-06-02T12:30-visual-device-gate` updated. VERSION left at
`1.5.0` because current unreleased 1.5.0 changes are still grouped under `[Unreleased]`.

## LATEST (2026-06-02, claude) — flag rename `--fidelity` → `--fit`
Renamed the clone reference-comparison gate FLAG `--fidelity` → `--fit` repo-wide (Claude
`claude-plugins/**` + Codex `codex-plugins/**` + canonical `templates/**` + docs/README/playbook/eval).
Only the literal flag token changed; the "fidelity" CONCEPT is untouched (agent `mp-fidelity-android`,
`fidelity-checklist-author`, `spec/fidelity/` & `build/fidelity/` paths, `fidelity_score`, epic
`fidelity`, the Fidelity-gate phase). Historical `.ai/changes/agent-skill-log.md` entries left verbatim
(append-only) + new entry `2026-06-02T10:00-rename-fidelity-flag-to-fit` added; CHANGELOG `[Unreleased]`
updated. **Note:** `D:\Pet\TDD_creater\MyMoney(_app)` has NO `--fidelity` flag (older `cmp`-prefix
bootstrap predating the gate) — nothing to rename there. Codex: pick up the log entry on next sync.

---

CURRENT TASK: mobile-pipeline marketplace — convert cmp into a multi-harness plugin marketplace
(`mp-spec` + `mp-dev`) modelled on `D:\tools\ai-team-bootstrap`; migrate diet_helper & MyMoney_app.
Approved plan: `C:\Users\k.shavrin\.claude\plans\noble-questing-muffin.md`. Brief: `.ai/tasks/claude-003-marketplace.md`.
STATUS: **DONE for v1.4.0** — marketplace + both plugins emitted/validated; 3 projects wired; docs +
VERSION + change-log updated. Branch: `feat/mobile-pipeline-marketplace`. **No commits yet** (awaiting
user go-ahead). Follow-ups + manual cleanup remain (below).

## DONE (claude, this session)
- **Phase 0** — verified plugin mechanics vs code.claude.com: Claude plugins carry `agents/`;
  `${CLAUDE_PLUGIN_ROOT}`; `enabledPlugins` object-map; Codex plugins = skills only (no sub-agents);
  local marketplace source `{"source":"directory","path":...}`.
- **Marketplace** — `.claude-plugin/marketplace.json` + `.agents/plugins/marketplace.json` (name
  `mobile-pipeline`, plugins `mp-spec` + `mp-dev`). `claude plugin validate .` ✔. Registered locally
  for test (`~/.claude/settings.json`); undo: `claude plugin marketplace remove mobile-pipeline`.
- **`lib/build-marketplace.sh`** — generator (canonical `templates/` → plugin trees). `bash -n` clean.
- **`mp-spec`** — `claude-plugins/mp-spec` (skill `/mp-spec` + 17 sub-agents + 25 prompts) +
  `codex-plugins/mp-spec` (skill only). 0 placeholder/tool leaks; validate ✔.
- **`mp-dev`** — `claude-plugins/mp-dev` (Claude-only): `/mp` + 11 agents + 2 scripts, de-specialized
  (runtime `.claude/mp/config.json` + `CLAUDE.md` + `.claude/mp/extras/*.md`; `${CLAUDE_PLUGIN_ROOT}`
  scripts). 0 leaks; scripts `bash -n` clean; validate ✔.
- **Projects wired** (downstream, outside this repo, additive + reversible — NO deletions):
  - `D:\Pet\TDD_creater\MyMoney` (spec staging) → `mp-spec`.
  - `D:\Pet\TDD_creater\MyMoney_app` → `mp-spec` + `mp-dev` + `.claude/mp/config.json` +
    `.claude/mp/extras/` (from `cmp-mymoney/`); `.codex` `max_threads` 4→6.
  - `D:\diet_helper` → `mp-spec` + `mp-dev` + `.claude/mp/config.json` + `.claude/mp/extras/`.
- **Docs/version** — `docs/MARKETPLACE.md` (full guide incl. manual-cleanup lists), README section,
  `install-spec.sh` superseded-note, `VERSION`→1.4.0, `CHANGELOG.md` [1.4.0], change-log entries
  (`2026-05-31T10:00/10:05/10:10`).

## OWNERSHIP BOUNDARY (re: codex-001 — respected)
- Did NOT edit `bootstrap.sh`, `lib/render.sh`, or `templates/**/scripts/*.sh` (codex-owned). The
  generator reads templates and writes transformed COPIES into the plugin trees only.
- `lib/build-marketplace.sh` is additive (claude-owned); may later merge with `lib/sync.sh`.

## ALSO DONE (later this session)
- **mp-spec plugin cleanup (codex)** — `lib/build-marketplace.sh` now rewrites marketplace output from
  legacy `app-spec-creator` naming to `mp-spec` and changes Claude spec-agent prompt reads to
  `${CLAUDE_PLUGIN_ROOT}/skills/mp-spec/prompts/...`. Regenerated `claude-plugins/mp-spec` and
  `codex-plugins/mp-spec`. Verified with bash syntax, dry-run generation, Claude plugin validation,
  leak greps, JSON parsing, `git diff --check`, and `python -m graphify update .`.
- **Folded** `mp-intake` / `mp-knowledge` / `mp-planner` (generic /mp-spec→backlog bridge) / `mp-improve`
  into canonical mp-dev (15 agents now) + orchestrator `--plan` / `--improve` + post-ship Knowledge step
  + `scripts/{{PREFIX}}-propose-improvement.sh`. validate ✔, 0 leaks.
- **Self-improvement → PR loop** implemented (mp-knowledge routes PLUGIN-LEVEL lessons → `/mp --improve`
  → mp-improve stages a templates/ patch → gated `propose-improvement.sh` branches+regenerates+PRs).
  Documented in `docs/MARKETPLACE.md` → "Improvement workflow".
- **diet_helper cleaned up** — generic `dh-*` + `dh.md` + scripts + PowerShell `build`/`test` +
  folded `dh-intake`/`dh-knowledge` MOVED to `diet_helper/.claude/_archive_pre_mp/` (never deleted).
  Uses `/mp` now; `selfimprove-retro.md` kept.
- **Codex model tiering (codex)** — `install-spec.sh --harness codex` now emits explicit
  `model` + `model_reasoning_effort` in every generated MP Spec TOML. The generated `mp-spec` skill
  documents the tiers, and `mp-dev` maintainer/command templates + marketplace docs now define the
  future Codex dev-agent tier contract (`mini` for mechanical/checking, `gpt-5.4` for standard
  authoring/analysis, `gpt-5.5` for frontier/critic work). Regenerated marketplace outputs and
  validated temp Codex install + manifests.

## NEXT / FOLLOW-UPS (open, ordered)
1. **User:** verify `/mp-spec` + `/mp` in a session (`/plugin` → enable).
2. **MyMoney_app dev migration** (deferred by design — bespoke `--phase`/`--check`/`--plan` + `cmp.md`
   depends on local `cmp-*`). Rewire `cmp.md` `cmp-*`→`mp-*` then archive generic `cmp-*`; verify. NOT a blind archive.
3. **Finish the local folder rename** — repo renamed on GitHub to `mobile-pipeline`; the working folder
   is still `D:\Pet\claude-mobile-pipeline` (cwd-locked). User: move it + repoint the 3 `directory`
   sources (or switch to the `git` source now that it's pushed). See final chat message.
4. Optional installer automation for per-project Codex **dev** agent shims. The `mp-dev` Codex skill
   and `templates/dev/codex/agent.toml.tmpl` now define the contract; future `lib/sync.sh` or
   bootstrap/install work can generate the 18 `.codex/agents/mp-*.toml` files automatically.
5. **[codex]** codex-001 (render `tool:` axis, `lib/sync.sh`, `bootstrap --tools`) still open + codex-owned.
6. Optional: run `graphify update .` when the local `graphify` command is available; the current
   PowerShell session could not find it.

## DECISIONS (+ why)
- Names: marketplace `mobile-pipeline`; `/mp` (dev), `/mp-spec` (spec). Unified `mp` prefix (user).
- `mp-dev` built from `templates/common`+`android` (generic, complete) via plugin-mode generator —
  not from MyMoney_app's `cmp-*` (which carry MyMoney-specifics). MyMoney_app keeps its project-
  specific `cmp-planner`/`--phase`/`--check`/`--device`/`--plan` local; generic agents come from plugin.
- Migration is ADDITIVE: marketplace + config + extras added; old local agents LEFT in place and
  listed for manual removal (never-delete rule). `cmp-*`/`dh-*` vs plugin `mp-*` names don't collide.
- mp-spec keeps `platform:` markers inert (matches install-spec); mp-dev strips them to android.

## CONTEXT LINKS
- Guide: `docs/MARKETPLACE.md`. Generator: `lib/build-marketplace.sh`. Brief: `.ai/tasks/claude-003-marketplace.md`.
- Reference pattern: `D:\tools\ai-team-bootstrap`.
