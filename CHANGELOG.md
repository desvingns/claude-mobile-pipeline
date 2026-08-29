# Changelog

All notable changes to `claude-mobile-pipeline` (cmp) are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
This repo uses [Semantic Versioning](https://semver.org/) — see `README.md` → Versioning.

## [Unreleased]

## [1.17.1] - 2026-08-22

### Fixed
- **GitHub push no longer requires `GITHUB_TOKEN`.** The standard runtime now uses the configured
  `origin` credential helper first, disables interactive credential prompts, and uses an explicit
  HTTPS token only as a fallback.
- **Codex chain hand-off matches the current task API.** The successor task is created with the
  exact chain command as its only initial prompt, so the runtime does not attempt an invalid empty
  prompt followed by a second message.

## [1.17.0] - 2026-08-21

### Changed
- **Codex backlog conveyor starts each SPEC in a new independent task.** `--feature --next --chain`
  now creates a local task with an empty conversation through `create_thread`; it never forks or
  inherits the previous task's turns, and it still refuses worktrees, branches, and non-`main`
  checkouts.

## [1.16.0] - 2026-08-21

### Added
- **Codex backlog conveyor: `--feature --next --chain`.** It keeps `--next`'s active-first,
  ordered-backlog resolution, then after a successful `active/ → done/` close forks one fresh
  local same-directory Codex task for the next runnable SPEC. The hand-off retains the selected
  model and reasoning effort, works directly in `main`, and never creates a worktree or Git branch.
  It deliberately stops when the board is drained, a verification/epic-close check fails, or an
  existing human gate still needs an answer.

## [1.15.0] - 2026-08-15

1.14.0 made the gates live; this release makes the loop around them terminate. A measured
six-hour SPEC spent 18% of its wall clock in recorded agent time and 65% waiting at a gate,
while semantic review produced findings that were all new across eight cycles.

### Fixed
- **Scoped runner addressed every module with `testDebugUnitTest`** — a regression shipped
  with `--scope` in 1.14.0. A scope containing a pure JVM module failed Gradle
  *configuration*, which the runner reported as a compile/config failure, so a healthy
  module looked broken and a developer was sent to find an error that was never there. The
  test task is now resolved per module (Android → `testDebugUnitTest`, JVM → `test`, both
  overridable via `MP_TEST_TASK`), each module's own result directory is scanned, and a
  missing module or absent task is reported as `"error_kind":"task_not_found"` — a different
  fact from "the tests failed" and no longer conflated with it.
- **The 1.14.0 capsule escalation always stopped for a human.** It now routes on the
  capsule's new `VERDICT`: `PATCH ALLOWED` continues automatically and records `gate_auto=1`;
  only `DESIGN DECISION REQUIRED` waits. On the measured run the gate cost 4 h 28 min waiting
  to approve a capsule that itself said no user decision was needed.

### Added
- **`{{PREFIX}}-spec-complexity.sh` — a SPEC size gate that runs before the first Developer
  call.** SPECs declare `Acceptance-matrix: role=owner,participant; state=active,grace,expired;
  transport=rpc,realtime`; the gate multiplies the dimensions and recommends a split above
  `acceptanceCellBudget` (default 24). Size is taken from the declaration, never from
  `CHANGED_HINT`, which on the run this exists for named two modules while the work crossed
  seven plus a server grant.
- **A frozen obligation matrix.** The gate expands the cross-product to a file, and every
  semantic pass must return `coverage` (`total`, `covered`, `uncovered[]`) against it instead
  of re-decomposing the problem. Successive passes had produced `STATE-001..008`,
  `SECURITY-001..004` and `TESTS-001..011` without repeating an ID — progress-shaped, but a
  random walk over an unbounded space.
- **Reviewer Check 8 (`usecase-test`)**: a touched use case with no dedicated `<Name>Test.kt`
  is rejected in milliseconds, instead of by the full verifier at the end of the run after
  the tests and reviews have already been paid for.
- **`--unattended`**, a modifier for any mode: advisory gates take their recommended default
  and are reported in a closing summary. Destructive or outward-facing gates — SPEC approval,
  `git push` — still stop and wait.
- **Agent liveness policy**: a semantic pass silent for 10 minutes is interrupted once and
  retried with a reduced evidence packet, then degrades to `partial` with `stalled=1` rather
  than blocking the chain.
- **Tester self-check** before returning: every `runBlocking` carries its
  `// {{PREFIX}}-real-io:` marker, no `@Ignore`, fakes not mocks, test names match. Two
  review→repair cycles on the measured run were spent adding markers to tests that were
  already correct.

### Changed
- **Telemetry covers phases, not just agents.** Every spawned agent records an event —
  including `tester` and `architect`, which recorded nothing before — and a `phase` event
  carries `human_wait_ms`. The retro now reports human wait separately from agent time and
  flags workflows with no phase accounting as wall-clock-unattributable. Recorded events had
  accounted for 18% of one SPEC's elapsed time.
- The two-cycle repair budget **does not reset** after a capsule; it becomes one final cycle,
  then a handoff.

## [1.14.0] - 2026-08-14

Closing the gaps a post-run analysis of one cross-layer SPEC exposed: four gates were
either not running, running against the change, or missing a contract entirely.

### Fixed
- The deterministic Android reviewer resolved exactly one source root
  (`app/src/main/java/<pkg>`), so on a multi-module project **every check silently
  skipped** and it always answered `{"pass":true,"violations":[]}`. Layers are now
  resolved per file — a `domain`/`data`/`presentation`/`ui` path component, or a
  `feature/*` module — covering both layouts and both `src/main/java` and
  `src/main/kotlin`. Test hygiene applies to every source set, not only `app/`.
- The risk router's keyword lists were English-only and its file globs lowercase, so a
  SPEC written in another language, crossing session auth, DI wiring, and bounded
  polling, scored 4 and routed to the cheap developer with no independent critic. The
  router now reads a declared `Risk-signals:` line, matches non-English prose, counts
  each signal once instead of once per file, and detects DI/persistence from file
  content rather than file names.
- The blanket "no `runBlocking` in tests" rule forced real MockWebServer/OkHttp tests
  under `runTest`'s virtual clock, where the production timeout expires before the real
  response lands. `runTest` remains the default; real-I/O tests opt out per call site
  with a `// <prefix>-real-io: <reason>` marker, and mixing a production timeout with an
  uncontrolled real callback is now itself a finding.
- Reviewer check 6b scanned a fixed 20-line window and reported healthy long tests as
  assertion-free; it now scans to the end of the test function.

### Added
- Reviewer check 7 — module dependency direction: layering inversion, declared cycles,
  and imports from a module the importer does not declare (the shape of a DI break that
  otherwise surfaces only at aggregate build time). Test-only configurations are
  excluded, and foundation modules (`common`/`util`/`model`/`kernel`/`shared`) rank below
  domain so a correctly layered project is not flagged.
- Reviewer `--warn-only` mode plus `"reviewerMode"` in project config, for adopting
  checks on a codebase they have never run against without blocking on day one.
- A semantic repair-loop contract: stable finding IDs, one batched holistic re-audit
  instead of per-cluster patching, a `resolved_findings` payload, a two-cycle budget, and
  escalation to a new `{{PREFIX}}-architect` PREFLIGHT capsule mode.
- An escalation ratchet: when the semantic reviewer reports `risk:"high"` or any blocker,
  the route rises to the powerful developer plus independent critic for the rest of the
  SPEC. Its verdict was previously recorded and discarded.
- Runner `--scope "<modules>"` for module-only unit tests with no lint/coverage/
  screenshots; the feature contract now iterates scoped and runs the full suite exactly
  once as the final gate.
- An epic-level `## Design capsule` written by the planner into `<epic>-00-overview.md`
  and injected into every backlog SPEC as `DESIGN_CAPSULE`. Backlog-consume mode skips
  Phase 0/1, so until now no step performed a design pass on a planned slice. Costs no
  extra agent call.

### Changed
- `duration_ms` and `correlation_id` are required at every telemetry record point;
  `repair_cycle`, `finding_ids`, `route_escalated`, and runner `mode` join the metric
  strings, and the retro reports instrumentation compliance before any cost conclusion.
- The reviewer's per-file work runs without subshells and collapses test hygiene into one
  `awk` pass — about 10x faster on a real diff, which is what keeps a cheap gate cheap
  enough to actually run.

## [1.13.0] - 2026-08-14

### Added
- Retro reports now mark pass-rate samples with fewer than three runs as ineligible,
  surface low-feedback events as reproducible evaluation candidates, and cluster
  concrete fail/partial evidence for human-gated follow-up.

## [1.12.1] - 2026-07-26

### Fixed
- Runner verification now trusts JUnit XML results and detects the coverage tool from the
  generated reports, avoiding false failures when the configured coverage command is absent.

## [1.12.0] - 2026-07-13

### Added
- **Lazy `/mp` runtime.** The former 83k-character command is now a compact router plus 15
  mode runbooks and 14 shared contracts. The fixed prompt falls by ~95%; each invocation reads
  only its selected workflow and declared contracts. Claude and Codex packages carry the same
  validated runtime.
- **Risk-based quality routing.** A deterministic helper selects standard/powerful Developer,
  focused semantic review, full/lite Verifier, and an independent critic for high-risk work.
  Safe fallback always chooses the stronger path.
- **MP Spec cost controls.** Content-addressed phase cache, compact evidence packets, conditional
  quality fan-out, deterministic preflight, failed-rubric-only retries, and normalized per-agent
  usage telemetry (`lean|balanced|max`) preserve mandatory artifacts and human gates.
- **Safe second-brain gateway.** Agents can read a token-bounded, tag-selected context and append
  fingerprinted candidates only to `brain/inbox/`; curated profile/domain/pipeline/project files
  remain read-only and promotion stays human-gated.
- **Incremental sync, eval, and proposal lifecycle.** `lib/sync.sh`, deterministic eval cases,
  applied/rejected proposal archives with receipts, telemetry-health detection, and correlation/
  cache/reasoning/duration fields close the learning loop.
- **Canonical Graphify update path.** Generated plugin copies and historical evidence are excluded
  from retrieval; the previous graph is archived before a forced canonical rebuild.

### Changed
- Bootstrap now emits lazy runtime files and every common deterministic helper, and renders the
  `{{AGENT_DIR}}` placeholder plus `tool:claude|codex` conditionals.
- Marketplace generation preserves the previous generated tree in `archive/marketplace/` instead
  of destructively clearing it; Codex mp-dev is self-contained with runtime references and scripts.
- CI validates Linux, macOS, and Windows, runs property/fuzz and deterministic eval suites, checks
  version parity, marker leaks, two-pass generator idempotence, and generated-tree drift.
- Second-brain collection now emits a capped summary plus on-demand evidence appendix and suppresses
  unchanged/no-signal heartbeat noise.
- Session startup reads `.ai/tasks/INDEX.md` plus active task files instead of bulk-loading history.

### Fixed
- Added the renderer functions for inline/multiline `tool:` blocks that the documented dual-tool
  contract already required.
- Hardened malformed MP Spec usage arguments and telemetry decimal validation so deterministic
  helpers always produce valid structured output instead of hanging or corrupting JSONL.
- Made global spec reinstall, Codex adapter replacement, proposal draining, and failed Graphify
  rebuilds preserve prior/user/partial evidence through explicit archives before replacement.
- Made brain digest names collision-safe, heartbeat mtime checks GNU/BSD portable, startup memory
  resolution gateway-only, and local exclusion policy configurable without shared sensitive terms.
- Restored the documented bootstrap `--no-git` flag and covered its warning-suppression behavior.

## [1.11.0] - 2026-07-05

### Added
- **Second-brain integration** (`{{PREFIX}}-knowledge`, `{{PREFIX}}-improve`, `{{PREFIX}}-reflect`).
  New BRAIN-LEVEL routing class in the knowledge agent: lessons that generalize beyond
  mobile-pipeline projects are appended as candidates to `$BRAIN/inbox/` (a private cross-project
  knowledge repo, e.g. `github.com/desvingns/brain`) and reported via a new `brain_candidates[]`
  output field; promotion into curated brain files stays human-gated (`/brain promote`).
- **Twin-pipeline awareness** (`{{PREFIX}}-improve`, `{{PREFIX}}-reflect`). Proposals now carry an
  optional `twin_applicability` field (applicable / twin_target / why) resolved against
  `$BRAIN/pipelines/TWINS.md`, so `/brain sync-twins` can stage ports into the twin me-dev
  pipeline. No behavior change when `$BRAIN` is not configured.

### Changed
- **User-profile path resolution** (`{{PREFIX}}-knowledge`): `$MP_USER_PROFILE` →
  `$BRAIN/core/user-profile.md` (when a second brain is configured) →
  `~/.config/mobile-pipeline/user-profile.md`.

## [1.10.0] - 2026-06-27

### Added
- **Developer version-bump on every commit** (`{{PREFIX}}-developer-android`). The developer now
  increments `versionName` PATCH (+1) and `versionCode` (+1) before staging on each `--feature` /
  `--bugfix` commit, so every pipeline build has a unique, traceable `versionName`; MAJOR/MINOR
  remain human-only.

### Changed
- **`--bugfix` repro-first discipline** (`{{PREFIX}}-developer-android`, `{{PREFIX}}-tester-android`,
  `/{{PREFIX}}`). For runtime/persistence/cold-start bugs the fix must be reproduced from the user's
  literal steps (not a self-authored hypothesis), a regression test that passes by construction is
  not proof, and cold-start/persistence regression tests must cross a real disk round-trip instead
  of reusing one in-memory store for write+read.
- **`/{{PREFIX}} --deliver` ordering.** The built artifact is now delivered to Telegram **before**
  the post-ship feedback question (you can't rate a result you haven't received), and auto-pick now
  excludes `*-androidTest.apk` so the app APK is sent rather than the instrumentation-test APK.

## [1.9.2] - 2026-06-19

### Fixed
- Plugin author metadata: `claude-plugins/{mp-dev,mp-spec}` and `codex-plugins/mp-spec` still
  showed a former corporate address; corrected to `Kirill Shavrin <desvingns@gmail.com>` to match
  the marketplace owner and the other manifests.

## [1.9.1] - 2026-06-19

### Changed
- `/mp --deliver`: the post-ship delivery offer now (a) fires on the **same epic-scoped timing** as
  the feedback question — once when an epic completes or a standalone SPEC ships, never after a
  non-final slice — and (b) on `y` **assembles a fresh artifact** (`./gradlew :app:assembleDebug`,
  stops on build failure) before sending, so the build delivered to Telegram includes the shipped
  changes instead of a stale APK. Wired into the **Epic completion (final review + close)** step.

## [1.9.0] - 2026-06-17

### Added

- **Telegram build delivery (`/{{PREFIX}} --deliver`).** New deterministic script
  `templates/common/scripts/{{PREFIX}}-deliver-telegram.sh` sends a built artifact (default: the
  newest `*.apk` under any `*/build/outputs/*`) to your own Telegram over an MTProto **user**
  session (Telethon) — so the file cap is 2 GB, not the bot API's 50 MB. Default target is `me`
  (Saved Messages); no bot and no local Bot API server required. Secrets (`TG_API_ID`,
  `TG_API_HASH`, `TG_SESSION`, optional `TG_TARGET`) are read from the environment or a gitignored
  repo-root `.env` (TG_* keys only, never executed). A one-time `--login` mode mints the
  `StringSession` interactively. Cross-platform bash wrapper; the MTProto call is delegated to
  `python3` + `telethon` (an external dependency, like adb/gradle). Emits exactly one JSON line and
  mirrors `ok` → exit code. Wired into the `/{{PREFIX}}` orchestrator as a documented step (Usage,
  Deterministic-steps, and **Workflow: --deliver** with a one-time-setup block and an optional
  post-build send offer). Ships in `claude-plugins/mp-dev` as `mp-deliver-telegram.sh`.
  See `docs/TELEGRAM-DELIVERY.md`.

## [1.8.1] - 2026-06-14

### Changed

- **Post-ship feedback is now collected once per epic, not per SPEC.** When the shipped SPEC
  belongs to a multi-SPEC epic (`<epic-slug>-NN-<short>.md` + an `-00-overview.md` index), the
  `/{{PREFIX}}` orchestrator asks the one feedback question ONLY when the ship completes the epic
  (no SPEC of that `<epic-slug>` left in `backlog/`/`active/`) — intermediate slices skip it
  silently so the user reviews the whole epic together. Standalone SPECs, `--bugfix`, and free-text
  `--feature <desc>` remain their own "epic" and are asked immediately. Reuses the same
  epic-completion detection introduced in 1.8.0.

## [1.8.0] - 2026-06-14

### Added

- **Epic completion (final review + close) in the `/{{PREFIX}}` orchestrator.** When the SPEC that
  just shipped (`active/ → done/`) is the last one of its epic (no `<epic-slug>-NN-*.md` left in
  `backlog/`/`active/`, only the `-00-overview.md` index), the orchestrator now runs a final review
  of the whole epic against ALL requirements listed in its `-00-overview.md` (every SPEC in `done/`
  with commit+files, the overview's goal + cross-cutting notes met by the union of ships) and, on a
  clean review, moves the `-00-overview.md` index `backlog/ → done/`. A gap blocks closure and the
  orchestrator proposes a follow-up SPEC instead. Fixes finished-epic overview files lingering in
  `backlog/`. Documented in the command's **SPEC backlog board** section, the `--feature --next`
  mode-select, and the Rules list (`templates/common/commands/{{PREFIX}}.md`).

## [1.7.1] - 2026-06-13

### Changed

- **Reverted the top-tier agents from Fable 5 back to Opus 4.8** (undo of 1.6.3). Fable 5
  (`claude-fable-5`) is currently unavailable on the host with no ETA, and the `model:` frontmatter
  field takes a single id — there is no automatic "fable → opus" fallback. To avoid those agents
  failing to launch, the explicit `claude-fable-5` id is replaced with the prior assignment:
  `{{PREFIX}}-developer-android` / `mp-developer-android` → `claude-opus-4-8`; mp-spec's
  `crawl-executor`, `crawl-reviewer`, `fit-checklist-author`, `screenshot-business-analyzer`,
  `screenshot-style-analyzer`, `spec-evaluator` (+ the evaluator rubric's model note) → `opus`.
  Re-apply 1.6.3 when Fable 5 becomes available.

## [1.7.0] - 2026-06-11

### Changed

- **`/mp --feature` Phase 1 is now grill-first** (mp-dev). The flat "ask ≤3 questions" step and the
  hard "Maximum 3 clarifying questions" rule are **removed**; Phase 1 now runs the same design-tree
  interrogation as `/mp-spec` — **always-on, ambiguity-scaled, no fixed question cap** (hard ceiling
  ≤12 as a backstop). Roots before branches, one decision at a time, each with a recommended answer,
  actively poking holes (assumptions / contradictions / unhandled states / scope creep). A trivial
  change (e.g. "new button → navigate to X") surfaces ~0 high-leverage unknowns and proceeds straight
  to the SPEC, so the fast path is preserved. `--spec` Phase 1 aligned to the same grill (lean to
  recommended defaults, grill only blocking forks). Backlog-consume mode (`--feature --next` /
  `--backlog`) still skips Phase 1 entirely. The grill protocol is inlined natively in
  `templates/common/commands/{{PREFIX}}.md` (no cross-plugin dependency on the mp-spec prompt copy).

### Added

- **Clone fidelity instrumentation (roadmap stage 6)** — design copying becomes
  measurement-driven. New `bounds-to-dp.sh` turns crawl element bounds into exact dp
  (checklists quote "FAB 56×56dp", not "density: normal"). New `{{PREFIX}}-pixel-diff.sh`
  (ImageMagick RMSE + heatmap, graceful `tool_missing`) powers a `--fit` **objective pixel
  pass**; the fit agent anchors `fit_score` to the pixel similarity and walks every checklist
  row with an explicit **pass/fail/uncheckable verdict**. Captures on BOTH sides (crawl and
  `--fit`) are normalized via Android demo mode + fixed font scale, with the AVD
  profile/density recorded. `apk-analyzer` Pass 7.5 **extracts real assets** (all fonts,
  launcher icon, notable drawables → `spec/assets/` with a personal-use legal caveat). Phase D
  writes machine-readable `spec/design-tokens.json`; the project's ui-designer **generates
  `Color.kt`/`Type.kt` directly from it** — the manual Material Theme Builder seam is gone for
  clones (kept as the greenfield fallback).
- **Clone completeness gates (roadmap stage 5)** — three deterministic gates so a visible
  button can no longer vanish silently. **Spec-time:** new crawl script `element-manifest.sh`
  distils uiautomator dumps into per-state interactive-element manifests; `fit-checklist-author`
  merges them into per-screen `spec/fit/elements/<Sxx>.json`; `spec-evaluator` gains **Class 5
  affordance coverage** (unmatched element = blocker) and a **clone-strict** profile
  (`orphan_screen`/`state_coverage_gap` escalate to blockers); GATE 2 prints every coverage-gap
  list explicitly. **Plan-time:** `--plan --phases` audits that every `registry.csv` screen and
  every `FR-`/`US-` id landed in ≥1 task — uncovered ids block the write until re-planned or
  explicitly deferred. **Build-time:** `--fit` captures the built screens' element trees and
  `{{PREFIX}}-fit-android` runs a structural element diff ahead of the visual pass (a missing
  expected element is a high-confidence major divergence). Crawl Phases 2–4 device validation
  (C10) still pending — tracked in claude-004/claude-010.
- **CI propagation + extended validation (roadmap stage 4)** — merged improvements now reach
  projects without manual steps. New `.github/workflows/regen-plugins.yml`: pushes to `main`
  touching `templates/**` (or the generator/render engine) regenerate the plugin trees and
  auto-commit them (loop-guarded via the paths filter; the PR drift gate makes it normally a
  no-op — it is the direct-push safety net). `validate-plugins.yml` extended: `bash -n` sweeps
  templates/selfimprove/eval/installers too, plus a new `shellcheck -S error` step.
  `selfimprove/README.md` gains "Scheduling the loop" (weekly host-side `/mp --reflect` via
  cron/Task Scheduler; keep `projects.txt` fresh) and `docs/MARKETPLACE.md` documents the
  propagation chain end-to-end.
- **Conveyor continuity + stale-test integrity (roadmap stage 3)** — `/{{PREFIX}}` (mp-dev).
  Phase 1 now ends with an **intent echo-back** ("Как я понял задачу" — goal, the one behaviour
  that must become true, out of scope) at the SPEC gate, catching a misread idea before any
  code. New **`--continue`** workflow: one re-entry point that inspects active SPEC → phase
  plan → backlog → clone fit state and proposes the single next command behind a y/N gate.
  **Phase-exit hook:** completing a phase auto-runs `--check`; on clones it offers `--fit`.
  **Stale-Test Update Rule:** the tester must reconcile old tests of MODIFIED pre-existing
  files (`stale_tests_reviewed[]` in its JSON, fed by an orchestrator-derived
  `MODIFIED_EXISTING` list) and the verifier gains **Check 6 `stale_tests`** blocking a push
  when changed behaviour left its old tests untouched and unreviewed. **`--fit` now enforces
  `fitThreshold`** from `.claude/mp/config.json` (default 85): below it — or with any
  unexplained divergence — the gate FAILs and the clone may not be declared done.
- **Cross-project user profile (roadmap stage 2)** — the pipeline now learns the USER across
  pet projects. New profile file `$MP_USER_PROFILE` / `~/.config/mobile-pipeline/user-profile.md`
  (taste / process / tech-default / anti-pattern facts, one bullet each with provenance,
  merge-not-duplicate rules) owned by `{{PREFIX}}-knowledge` via a new `user_preference` routing
  category. Both grills read it — `/{{PREFIX}} --feature` Phase 1 (Startup step 3) and the
  `/mp-spec` grill + greenfield stage defaults (grill-me v1.2.0) — to bias **recommended
  answers only** (cited in a short parenthetical; never auto-decides; absence changes nothing).
  `{{PREFIX}}-fit-android` gains optional `taste_signals[]` (preference candidates inferred from
  *intended* deviations) which `--fit` offers to record behind a y/N gate; the post-ship
  feedback note flags durable "always/never" statements as profile candidates.
- **Self-improvement loop now feeds itself (roadmap stage 1)** — run telemetry, retro nudges,
  and a post-ship feedback question in `/{{PREFIX}}` (mp-dev). New pipeline scripts
  `{{PREFIX}}-record-run.sh` (appends one JSON event per pipeline step to
  `<repo>/selfimprove/runs/`, accepts `--tokens-in/--tokens-out/--cost` estimates, reports
  `retro_due` after ≥10 unreflected events) and `{{PREFIX}}-retro.sh` (deterministic per-project
  retro: per-agent pass-rate, user-feedback scores, token/cost totals, failure tail). The
  orchestrator records fire-and-forget events after reviewer / final-runner / verifier / fit,
  offers the retro when due, asks ONE post-ship feedback question (score 1–5 + note; ≤3 appends
  a lesson to `selfimprove/lessons.md` and feeds `mp-knowledge`'s SESSION_RECAP), and nudges
  `--improve --drain` when ≥3 proposals are queued. Telemetry never blocks a run. Root
  `selfimprove/` kit updated for parity.
- **Improvement roadmap from the goals audit** — new `docs/IMPROVEMENT-ROADMAP.md`: a 46-item
  catalog (self-improvement loop, cross-project user memory, clone completeness, design
  fidelity, infra) graded against the two project goals, with evidence pointers into
  `templates/` and six queued task briefs (`.ai/tasks/claude-006…011`) staging the work
  loop-first. Docs-only — no agent behaviour changed.
- **Grill-me design-tree interrogation** in `/mp-spec` intake — a reusable orchestrator technique
  (`prompts/techniques/grill-me.md`; not an agent) that interviews **one adversarial question at a
  time**, resolving the app as a *tree of decisions* (roots before branches), offering a
  recommended answer for each, and actively poking holes (hidden assumptions, contradictions,
  unhandled states, scope creep). **Greenfield** runs it as a mandatory **Stage 0** (escape hatch
  `--no-grill`) right after the idea paragraph, writing a decisions ledger
  (`input/interview/grill.md`) that grounds the 5 interview stages + GATE 1 — so a thin idea is no
  longer answered by guessing. **Clone** grills the analyzers' `ambiguities[]` / `state_gaps[]`
  (dependency-ordered, one at a time) instead of a flat dynamic batch, writing `pipeline/grill.md`.
  Additive: no new agent (no installer/roster change), propagates via the prompt-library copy.
- **Dynamic reference-APK crawler (Phase 1)** for `/mp-spec` clone intake — a new optional Phase A.0
  that installs the reference APK on a connected device and drives it **vision-first** to build a
  state graph with screenshots, dedup states, and fill `input/screenshots/` with an *observed* corpus
  (replacing hand-collected screenshots). Adds five cross-platform device primitives
  (`scripts/crawl/{device-preflight,app-control,screencap,ui-dump,input}.sh`, each emitting one JSON
  line), the `crawl-executor` agent (opus; vision-first BFS + state dedup + a forbidden-action
  guardrail), `--graph`/`--no-graph` flags, and the `clone.crawl-setup` device/consent prompt.
  Additive: auto-skips to the static path when no device is reachable or the APK won't run.
  Device-validated on an emulator (Android 34) — fixed MSYS `/sdcard` path mangling on Git Bash,
  Compose tap-by-text resolution (label on a non-clickable node), and launch foreground-confirmation.
  Phases 2–4 (navigator/executor/reviewer trio, autonomous data-seeding, fit wiring) are tracked
  in `.ai/tasks/claude-004-reference-crawler.md`.
- **Reference-APK crawler (Phase 2) — agent trio + coverage gate.** Split the single-agent crawler into
  three separate-session sub-agents — `crawl-navigator` (plans the next affordance + replay path),
  `crawl-executor` (goal-scoped vision-first device driver), `crawl-reviewer` (classifies the resulting
  edge flow/cycle/error/dead_end + scores coverage confidence) — run by an orchestrator loop with a
  max-2-retry `executor⇄reviewer` inner loop (mirrors the Phase F evaluator-optimizer) and a
  done/plateau/budget stop, all state persisted to files for crash-recovery. `navigation-flow-analyzer`
  now consumes the observed `state-graph.json`, converting walked transitions to `source:observed`
  edges (mapping crawl `ST*` → business `S*` via the shared screenshot filename) and inferring only the
  transitions the crawl didn't reach.
- **Reference-APK crawler (Phase 3) — autonomous seeding + auth.** The crawl now observes **populated**
  states, not just empties. `crawl-navigator` emits `auth` goals (get past a sign-in/onboarding wall —
  unblock before breadth) and `seed` goals (create entries to reveal an empty state's filled form);
  `crawl-executor` fills forms with deterministic **synthetic** data (user-provided test credentials if
  given, else self-registers), creates N entries, and captures the `data_state:"filled"` result;
  `crawl-reviewer` judges auth/seed success from the after-screenshot. Guardrails: synthetic data only,
  no real-money/send/share, and SMS/email-OTP/captcha walls become `needs_human` (accept-and-prune, no
  retry). New consent modes (`seed` / explore-only / decline) + an optional test-credentials question in
  `clone.crawl-setup`; credentials are runtime-only and never written to any artifact.
- **Reference-APK crawler (Phase 4) — closes the clone loop.** `fit-checklist-author` now consumes
  the crawl's observed per-state frames: it grounds per-screen must-match checklists in the real empty
  *and* filled states (the `data_state:"filled"` ones seeding produced), writes a visual block per state,
  and emits a `registry.csv` row per (screen, state) — so `--fit` drives the built app into each state
  and compares it against its own reference frame, killing the empty-state class of divergence. New
  `docs/REFERENCE-CRAWLER.md` consolidates the subsystem; `docs/CLONE-PLAYBOOK.md` gains the crawl
  front-door (Step 0) + updated loop diagram. The crawler is now feature-complete across all four phases
  (device primitives → trio + coverage gate → autonomous seeding/auth → fit wiring).
- **Codex `mp-dev` marketplace bridge** - added `codex-plugins/mp-dev` with the `$mp`/`/mp` skill,
  UI metadata, and a `codex-agent-shims` reference for the 18 native project-local
  `.codex/agents/mp-*.toml` wrappers. The bridge reads the canonical Claude `mp-dev` command and
  agent bodies plus `.claude/mp/config.json` / `.claude/mp/extras/*`, documents the Bash-absent
  fallback path, and keeps Claude/Codex project-specific improvements synchronized through the shared
  extras layer.

### Changed

- **Per-project device-run helper is now first-class in `mp-runner-instrumented-android`** — the
  instrumented runner's Step 2 override now also discovers the helper in the project's per-agent
  extras (not only `CLAUDE.md`) and explicitly sanctions invoking a PowerShell host-AVD helper from
  the Bash tool (e.g. `powershell.exe -File scripts/<helper>.ps1 -TestClass '<FQN>'`) as the
  documented exception to the Bash-only default — still parsing the report, never the exit code. Lets
  Windows host-AVD projects (where AGP UTP rejects a `:`-serial) run `--device` slices through their
  helper instead of the bare `connectedDebugAndroidTest`. Surfaced by the MyMoney clone migration.
- **Renamed the `fidelity` concept to `fit` repo-wide** (completing the 1.5.0 flag-only `--fidelity` →
  `--fit` rename). Agents `fidelity-checklist-author` → `fit-checklist-author` and
  `{{PREFIX}}-fidelity-android` → `{{PREFIX}}-fit-android` (generated `mp-fit-android`); bundle dir
  `spec/fidelity/` → `spec/fit/`, build output `build/fidelity/` → `build/fit/`; `fidelity_score` →
  `fit_score`; the Fidelity-gate phase → Fit-gate; the `=== FIDELITY ===` payload markers → `=== FIT ===`;
  and `eval/clone-fidelity/` → `eval/clone-fit/`. **Breaking:** the renamed agents change generated
  plugin filenames — downstream projects referencing `mp-fidelity-android` / `fidelity-checklist-author`
  or `spec/fidelity/` paths must update. (Released 1.5.0 history below intentionally keeps "fidelity".)

## [1.6.3] - 2026-06-09

### Changed

- **Top-tier agents moved from Opus 4.8 to Fable 5** (`claude-fable-5`). mp-dev:
  `{{PREFIX}}-developer-android`. mp-spec: `crawl-executor`, `crawl-reviewer`,
  `fit-checklist-author`, `screenshot-business-analyzer`, `screenshot-style-analyzer`,
  `spec-evaluator` (+ the evaluator rubric's model note). The generic `model: opus`
  shorthand in those agents is replaced with the explicit `claude-fable-5` id. If a host
  Claude Code build does not recognise Fable 5, set those agents back to
  `claude-opus-4-8` manually (the previous assignment).

## [1.5.0] — 2026-06-02

### Changed

- **Visual/device autotest pre-flight gate for Android `/mp` work** — explicitly visual tasks
  (`visual`, layout, theme, animation, screenshot, fidelity/reference comparison, visual QA,
  `instrumented-compose-ui`, `--device`, `--fit`, or visual device done-criteria) must confirm a
  usable booted device/emulator before implementation/test execution. If absent, the orchestrator
  stops and asks the user to connect the required device; JVM-only checks and screenshot baselines
  may not be claimed as device visual verification.
- **Renamed the clone reference-comparison gate flag `--fidelity` → `--fit`** across the
  orchestrator command, agent docs, skill prose, templates, the clone playbook and the README
  (Claude + Codex). Only the flag token changed — the "fidelity" concept (agent names, the
  `spec/fidelity/` bundle, `fidelity_score`, the Fidelity-gate phase) is unchanged. Breaking for
  anyone scripting `/<prefix> --fidelity`: use `/<prefix> --fit`.
- Codex spec-agent shims generated by `install-spec.sh --harness codex` now pin explicit
  `model` and `model_reasoning_effort` tiers instead of inheriting the parent session's model.
  The same fast/standard/powerful tier contract is documented for future Codex `mp-dev` shims.

## [1.4.0] — 2026-05-31

### Added

- **Multi-harness plugin marketplace (`mobile-pipeline`)** — cmp can now be consumed as a plugin
  marketplace (modelled on the multi-harness `ai-team-bootstrap` pattern), not only copy-per-project
  via `bootstrap.sh`. New `.claude-plugin/marketplace.json` (Claude) + `.agents/plugins/marketplace.json`
  (Codex) list two plugins:
  - **`mp-spec`** — the `app-spec-creator` skill (invoked as `/mp-spec`) + its 17 sub-agents →
    `claude-plugins/mp-spec/` (Claude: skill + agents) and `codex-plugins/mp-spec/` (Codex: skill
    only — Codex plugins can't carry sub-agents; the `.codex/agents/*.toml` roster stays per-project).
  - **`mp-dev`** — the dev orchestrator (`/mp`) + specialist agents + deterministic scripts →
    `claude-plugins/mp-dev/` (Claude-only). De-specialized: generic agent bodies read project facts
    from `.claude/mp/config.json` + `CLAUDE.md` + `.claude/mp/extras/*.md` at runtime; scripts resolve
    via `${CLAUDE_PLUGIN_ROOT}`.
- **`lib/build-marketplace.sh`** — generator that emits both plugin trees from the canonical
  `templates/` (one source → per-tool adapters). `bootstrap.sh` and `templates/**/scripts/*.sh` are
  untouched, so the legacy copy-per-project bootstrap stays byte-compatible.
- Projects consume the marketplace via `.claude/settings.json` (`extraKnownMarketplaces` +
  `enabledPlugins`). Wired into `diet_helper`, `MyMoney_app`, and the MyMoney spec-staging folder.
- **Folded into canonical `mp-dev`**: `{{PREFIX}}-intake` (SPEC synthesis from Q&A), `{{PREFIX}}-knowledge`
  (post-ship lesson routing), `{{PREFIX}}-planner` (the `/mp-spec` bundle → `.claude/specs/backlog/`
  bridge, generic — replaces MyMoney's PROGRESS.md-specific planner), and `{{PREFIX}}-improve`. New
  orchestrator workflows `--plan` and `--improve` + a post-ship Knowledge step.
- **Self-improvement → PR workflow**: a lesson found while running `/mp` in a downstream project can be
  routed by `{{PREFIX}}-knowledge` as PLUGIN-LEVEL → `/mp --improve` drafts a patch against the
  canonical `templates/` (via `{{PREFIX}}-improve`) and, behind a gate, branches mobile-pipeline,
  regenerates the plugin trees, and opens a PR (`scripts/{{PREFIX}}-propose-improvement.sh`). Project
  source is never touched; mobile-pipeline is changed only via a reviewed PR.
- **diet_helper migrated to `/mp`**: its generic `dh-*` agents, `dh.md`, deterministic scripts, and the
  PowerShell `build`/`test` commands moved to `.claude/_archive_pre_mp/` (reversible; never deleted).
- **Batch + cross-project + CI for the improvement loop**: `--improve "<note>"` opens its OWN PR;
  `--improve --drain` batches ALL queued proposals (auto-staged by `mp-knowledge` / `mp-reflect`) into
  ONE PR (`scripts/{{PREFIX}}-improve-drain.sh`). New `--reflect` aggregates self-improvement lessons
  across all projects (`scripts/{{PREFIX}}-cross-reflect.sh` + `{{PREFIX}}-reflect` agent, projects from
  `~/.config/mobile-pipeline/projects.txt`) and queues improvements for patterns seen in ≥2 projects.
  A GitHub Actions CI gate (`.github/workflows/validate-plugins.yml`) runs on every PR: JSON-manifest
  validity, `bash -n`, placeholder/marker leak check, and a **regeneration-drift** check (committed
  plugin trees must equal `./lib/build-marketplace.sh` output).
- **SPEC backlog board** — `.claude/specs/` in a generated project is now a file-based task board
  (`backlog/` / `active/` / `done/`; a SPEC's status is the folder it lives in). The orchestrator's
  `--feature` Phase 1 splits a large feature into ≥2 ordered SPEC files written to `backlog/`
  (behind one y/N gate), promotes the first to `active/`, then moves it to `done/` on ship. Epics
  group by a `<epic-slug>-NN-<short>.md` filename prefix + an optional `-00-overview.md` index. New
  `## SPEC backlog board` section + a Rules bullet in `templates/common/commands/{{PREFIX}}.md`;
  full contract in `templates/common/specs/README.md`; `bootstrap.sh` now emits the
  `backlog/active/done` board folders (each with a `.gitkeep`) into new projects.
  Additive — single-SPEC features and the `--discuss` brainstorm-artifact flow are unchanged.
  (VERSION bump to 1.4.0 deferred to release time per SemVer: additive = MINOR.)
- **`--spec` + backlog-consume** — `/{{PREFIX}} --spec <desc>` authors SPEC(s) and writes them
  straight to `.claude/specs/backlog/` as `Status: draft` (no code, no approval gate) — fills the
  backlog ahead of time. `/{{PREFIX}} --feature --next` (or `--backlog <slug>`) implements a SPEC
  already in the backlog: it is treated as already created + approved, so Phase 0/1 are skipped —
  the file moves `backlog/ → active/`, runs Phase 2, then `active/ → done/`. Usage block, Rules,
  and the specs-README lifecycle (new `draft` status) updated accordingly.

## [1.3.0] — 2026-05-29

Spec-creation half: a global `app-spec-creator` spec pipeline and its installer. Produces a
complete, traceable `spec/` bundle from a brand-new app idea (greenfield interview) or from
screenshots of an existing app (clone). Dual-harness: installs once into `~/.claude/` and/or
`~/.codex/` via `install-spec.sh`.

### Added

- **`templates/spec/`** — new template group: 17 canonical agent specs
  (`templates/spec/agents/*.md`), the `app-spec-creator` skill
  (`templates/spec/skills/app-spec-creator/SKILL.md`), and an independently-versioned prompt
  library (`prompts/`). Supersedes `app-tdd-creator` (kept as deprecation shim).
- **`install-spec.sh`** — global installer. Flags: `--harness claude|codex|both` (default
  `both`), `--home DIR`, `--dry-run`, `--force`. Claude form: copies skill + 17 `.md` agents
  into `~/.claude/`. Codex form: copies skill + `.md` agents + generates `.toml` native
  subagent shims + appends `[agents]` to `~/.codex/config.toml` (`max_threads=6`,
  `max_depth=1`).
- **Codex adapters** — per-agent `.toml` shims (re-read the canonical `.md`) so specialists
  run as native Codex subagents; `config-fragment.toml` with the required `[agents]` settings.
- **Spec→dev handoff docs** — portable handoff path (`traceability.csv` + `design.md` +
  `acceptance/*.feature`) described; optional per-project spec-bridge pattern documented
  (reference: MyMoney `cmp-planner-android`); generic `--from-spec` dev-pipeline flow noted
  as a known follow-up (deferred until `lib/sync.sh` `tool:` strip lands).
- **`docs/SPEC-PIPELINE.md`** — full guide: overview of both cmp halves, install, `spec/`
  bundle anatomy, 17-agent table, two intake modes + two gates + evaluator loop, dual-harness
  mechanics (Claude vs Codex, `.toml` shim idiom, config caveat), and spec→dev handoff.

### Migration notes (1.2 → 1.3)

- No changes to existing per-project dev-pipeline templates. `bootstrap.sh` and all `templates/
  {common,android,ios}/` are unchanged — existing projects are unaffected.
- Run `./install-spec.sh` once to get the spec tool globally. Existing `~/.claude/skills/
  app-spec-creator/` (if any, from a pre-template install) must be removed or use `--force`.

## [1.2.0] — 2026-05-28

On-device instrumented testing. The pipeline gains a dedicated runner for
`connectedDebugAndroidTest` and a small `--device` workflow that writes and runs ONE Compose-UI
test on a connected device/emulator at a time — sized so a less-capable model stays on rails.
A connected device is now mandatory for on-device runs, with an ask-the-user-and-remember rule.

### Added

- **`{{PREFIX}}-runner-instrumented-android`** — new Android agent (model: haiku) that runs ONE
  instrumented test class on a connected device/emulator and returns parsed pass/fail JSON. Trusts
  the connected report XML, never "BUILD SUCCESSFUL". A connected device is mandatory; with none it
  returns a "no device connected" error (it cannot prompt — the orchestrator asks). Distinct from the
  JVM-only `{{PREFIX}}-runner-android`.
- **Orchestrator** — new `--device <screen|scope>` workflow (Android only): mandatory device-connection
  gate (ask the user + record to the `device-connection` memo if missing/lost), then write ONE
  instrumented Compose-UI test for an uncovered control → run via the instrumented runner → report.
  One control per invocation; never pushes.
- **`device-connection` memory template** (android) — records the verified device/emulator connection
  so it is not re-asked; the mandatory/ask/update-if-lost rule lives here.
- **`{{PREFIX}}-tester-android`** — new "instrumented-compose-ui (on a real device)" test type:
  one `@Test` per `--device` slice, real-device `AndroidJUnit4` + `createComposeRule` pattern, strings
  via resources, missing-seam policy (testTag/contentDescription/public only, never invent UI).
- **`{{PREFIX}}-developer-android`** — new "Device-test seams" section: a `--device` seam is limited to
  testTag / contentDescription / `<Name>Content` public visibility; no new UI/events.
- **`{{PREFIX}}-reviewer-base`** — Check 7 (Device-test seam scope): a `--device` production diff must
  not add behaviour beyond a declared seam.

### Changed

- `bootstrap.sh` dry-run preview lists the new `runner-instrumented-android` agent (the copy loop
  already globs `templates/<plat>/agents/*.md`, so it is generated automatically).

### Migration notes (1.1 → 1.2)

- Re-bootstrap, or copy the new files by hand: `templates/android/agents/{{PREFIX}}-runner-instrumented-android.md`
  and `templates/android/memory/device-connection.md.tmpl`, plus the `--device` workflow + Rules in
  `templates/common/commands/{{PREFIX}}.md` and the device sections in the tester/developer/reviewer
  templates. No existing agent signatures changed — purely additive.

## [1.1.0] — 2026-05-19

Test-coverage hardening: the pipeline now enforces "every new prod class has a dedicated
test file" and "tests are clean" alongside the existing layer-boundary checks. Runner gains
Android Lint and JaCoCo coverage threshold. New optional `--coverage` workflow surfaces
weak packages on demand. Design notes for local-LLM delegation added but not yet
implemented.

### Added

- **`{{PREFIX}}-tester-<plat>`** — new "Mandatory Coverage Rules" section. Every new prod
  file in CHANGED_FILES requires a matching dedicated test file (no use-case grouping).
  Return JSON gains `missing_content_extraction` and `coverage_exceptions` fields.
- **`{{PREFIX}}-tester-android`** — new "navigation" test type for `AppNavHost.kt` changes
  (TestNavHostController pattern).
- **`{{PREFIX}}-runner-android`** + script — adds Android Lint (`:app:lintDebug`) and
  JaCoCo coverage threshold (`:app:jacocoUnitTestReport` → XML parse, default 65%). Return
  JSON gains `lint` and `coverage` fields. Script takes second positional arg
  `target_coverage_pct`.
- **`{{PREFIX}}-runner-ios`** — `target_coverage` support via xccov parsing.
- **`{{PREFIX}}-reviewer-base`** — Check 6 (Test Hygiene): bans `@Ignore` without
  TODO/issue ref, empty `@Test`, trivially-true assertions, `Thread.sleep`, `runBlocking`
  in tests.
- **`{{PREFIX}}-reviewer-android`** + script — concrete grep commands for Check 6.
- **`{{PREFIX}}-verifier-<plat>`** — Check 5 (`tests_exist`): for each new prod file, the
  matching dedicated test file must exist (or be explicitly excepted by tester).
- **`{{PREFIX}}-coverage-android`** — new on-demand read-only agent that parses JaCoCo XML
  and reports weak packages with concrete "test this next" suggestions.
- **Orchestrator** — new `--coverage [<scope>] [--target=N]` workflow (Android only,
  diagnostic, read-only).
- **`docs/local-llm/`** — design notes for delegating shaped/mechanical subtasks to a small
  local LLM (≤6 GB VRAM): models, integration options (MCP / bash-curl / router), task
  ranking (Tier S / A / B / F), draft prompts, failure modes. **No implementation in cmp
  v1.1 — these are notes for a future iteration.**

### Changed

- `templates/common/agents/{{PREFIX}}-reviewer-base.md` Concept section grows from four
  layer-boundary checks to six (adds design-system and test-hygiene concepts at the
  framework-agnostic level).
- Runner agent JSON shape gains `lint` and `coverage` keys — projects upgrading from 1.0
  must update any logic that parses the runner output.

### Migration notes (1.0 → 1.1)

- Re-bootstrap or merge templates by hand. The reviewer / runner script signatures changed
  (runner accepts a second positional arg). Orchestrators in already-shipped projects can
  continue passing only the first arg — coverage defaults to 65 when omitted.
- If your project does not yet have `jacocoUnitTestReport` configured in `app/build.gradle.kts`,
  the runner's Step 4 will emit `"coverage": "unknown"` and fail-close. Either add the
  JaCoCo task (recommended, see `diet_helper/app/build.gradle.kts` for a working example)
  or pass `target_coverage=0` to disable the gate.
- Existing test files with grouped use-case tests (`<Group>UseCasesTest.kt`) are tolerated;
  the no-grouping rule applies only to NEW use cases added after upgrade.

## [1.0.0] — 2026-05-18

Initial release. Templates extracted from the `diet_helper` Android project after
6 iterations of in-project refinement (memory infra, STATE/ROADMAP artifacts, brainstorm
phase, verification gate, TDD red-green mode).

### Added

- Repo skeleton: `templates/{common,android,ios}/`, `lib/`, `docs/`, `eval/`, `examples/`.
- `bootstrap.sh` — single entry point, copy + render + memory + version stamp.
- `lib/render.sh`, `lib/detect.sh`, `lib/prompts.sh` — cross-platform helpers (Linux + macOS + Windows Git Bash).
- Common agents (platform-agnostic): `architect`, `docs`, `reviewer-base`.
- Common command: `<prefix>.md` orchestrator with `--discuss`, `--feature` (default + `--tdd`), `--bugfix` workflows; Phase 0 brainstorm trigger; Step 4.5 verification gate.
- Common snippets: `green-phase-mode.md`, `test-rules.md`, `manual-checklist-prompt.md`, `runner-json-shape.md`.
- Common root templates: `CLAUDE.md.tmpl`, `STATE.md.tmpl`, `ROADMAP.md.tmpl`, `DOCUMENTATION.md.tmpl`.
- Common memory: 6 generic templates + index generator.
- Android agents: `developer-android`, `tester-android`, `verifier-android`, `reviewer-android`, `runner-android`.
- Android snippets: `jbr-detect.sh`, `gradle-commands.md`.
- Android memory: `cross-platform-bash-jbr`, `dao-test-config-trap`, `room-upsert-by-pk-not-unique`, `screen-content-extraction`.
- iOS stubs: developer / tester / verifier / reviewer / runner — minimal frontmatter + TODO sections.
- iOS snippets: `xcode-detect.sh`.
- iOS memory: `cross-platform-bash-xcode`, `view-extraction`.
- Docs: `USAGE.md`, `CUSTOMIZATION.md`, `UPGRADE.md`, `ADDING-PLATFORM.md`, `ARCHITECTURE.md`.
- `eval/README.md` — placeholder for future eval framework.

### Not included (deferred)

- `bootstrap.sh --upgrade` — manual upgrade flow. Add when ≥1 project needs to pull cmp improvements.
- Real iOS agent content beyond stubs — fill in when first iOS project starts.
- Eval framework (`cmp-grader` agent) — add after ≥10 pipeline runs accumulate as eval cases.
- Vector DB for memory — current plain-MD + index is sufficient at ≤15 memos per project.
- PostToolUse hooks for output sandboxing — runner-level `grep | tail` is sufficient until proven otherwise.
