---
name: mp-spec
description: Builds a complete, testable, traceable specification BUNDLE for a mobile app (Android now, iOS-ready) and hands it off to development. Two intake modes that converge on one artifact set — GREENFIELD (staged interview elicitation for a brand-new app) and CLONE (screenshots + Google Play + optional APK, reusing the analyzer agents). Produces EARS requirements, user stories, Gherkin acceptance criteria, a platform-neutral design doc + platform appendix, NFR/a11y/security/analytics/i18n/risk/estimate artifacts, and a traceability matrix — validated by an evaluator-optimizer critic with two human gates. Supersedes app-tdd-creator. Triggers on "/mp-spec", "сделай спеку приложения", "собери требования по приложению", "spec bundle", "TDD по скриншотам", "воссоздай приложение", "придумай приложение с нуля". Use when the user wants structured requirements/specs for a mobile app — whether cloning an existing app or designing one from scratch — for handoff to coding agents.
---

# /mp-spec — Universal-Intake Spec Pipeline

You orchestrate a multi-agent pipeline that produces a **spec bundle** (`spec/`) for a mobile app and hands it to development (your project's dev pipeline — e.g. `/cmp --plan <bundle>` — via the handoff step). Two intake modes converge on one shared artifact set, so everything downstream is mode-agnostic.

This skill **supersedes** `app-tdd-creator` (which produced only a single TDD). It keeps that skill's proven analyzer fan-out and question-batching, adds a greenfield front-door, a validation critic, and the missing artifact types (testable requirements, NFR, a11y, security, analytics, i18n, risk, estimate, traceability), and emits a platform-neutral bundle so iOS can be added later without rework.

## Language rules (hard)

- This SKILL.md, agent prompts, prompt-library files, intermediate `pipeline/*.md`: **English**.
- Verbatim quotes (Google Play text, screenshot text, user's interview answers): **preserve original language**.
- Final bundle prose (`design.md`, `product-brief.md`, narrative parts): **Russian** by default (override per Q-A4).
- Requirement/AC IDs, code identifiers, Gherkin keywords: **English** always.
- Chat responses to the user: **Russian**. AskUserQuestion: questions/labels Russian, internal IDs (A1, B2, …) Latin.

## Scope rule (hard)

This skill produces the **spec bundle** and (on request) triggers the handoff. It does **not** write production Kotlin/Swift, Compose/SwiftUI, or run builds — that is the dev pipeline's job, fed by the handoff. If asked to code during this run, defer: «Этот скилл готовит спеку и хендофф. Кодогенерация — в дев-пайплайне (`/<prefix>`).»

**Personal-project scope.** This is personal tooling. Never pull in organization-specific work
agents, skills, issue trackers, chat systems, or private plugins.

## Prompt library (include-by-reference)

Detailed question banks, rubrics, and templates live under `prompts/` next to this file, **not** inlined here. When a step says `Read prompt <id>`, open `prompts/<id>.md` and follow it. Index: `prompts/README.md`. This keeps the orchestrator thin and the rubrics independently versioned — bump a prompt's `version` to upgrade every consumer at once.

## Harness notes (Claude vs Codex)

This skill runs under **both** Claude Code and Codex CLI. The orchestration is identical; three touch-points differ by harness:

- **User gates** have no structured-question tool — **ask the question in chat and STOP** until the user replies. Never proceed past a gate without an answer.
- **Specialists** run as native Codex subagents (`.codex/agents/<name>.toml`). Request them by name; for a parallel phase, request all and **wait for every JSON result** before continuing (concurrency is bounded by `[agents] max_threads`, so a 5-way fan-out may queue — fine). Workers must not spawn descendants (`max_depth=1`).
- **Model tiers** are pinned in each generated Codex TOML, not inherited from the parent session: simple scrapers/constitution use `gpt-5.4-mini`, most authoring and analysis roles use `gpt-5.4`, screenshot analyzers use `gpt-5.6`, and `spec-evaluator` uses `gpt-5.6` with `xhigh` reasoning. Do not override those tiers ad hoc unless the task explicitly calls for it.
- Skill lives inside the `mp-spec` plugin; Codex sub-agent shims are installed separately; prompts live next to this SKILL.md under `prompts/`.

## Step 0 — Parse input & detect mode

**Slash form:** `/mp-spec [<screenshots_dir>] [--apk <path>] [--play <url>] [--greenfield] [--feature] [--board <dir>] [--epic <slug>] [--name <APP>] [--platforms android[,ios]] [--depth mvp|production|reference] [--base <dir>] [flags]`

**Mode detection:**
- `--feature` present, OR (invoked from inside an existing project that has a `.claude/specs/` board AND the input is a feature description, with no clone inputs) → **feature** mode (brownfield: spec a feature into the project's backlog board — NOT a whole-app `spec/` bundle).
- Any of `<screenshots_dir>` / `--apk` / `--play` present → **clone** mode.
- None of the above, or `--greenfield` → **greenfield** mode.
- `--mode feature|greenfield|clone` overrides detection.

**Flags** (superset of app-tdd-creator's): `--name`, `--depth {mvp|production|reference}`, `--budget {lean|balanced|max}` (default `balanced`; controls model/critic spend, never removes mandatory artifacts or gates), `--platforms` (default `android`), `--base` (output root; default `~/AppSpecs` — a personal folder you control, kept separate from any unrelated work context), `--resume`, `--fresh`, `--dry-run`, `--skip-play`, `--skip-apk`, `--only <list>`, `--only-failed-rubrics` (resume an evaluator failure and rerun only owning artifacts/check classes), `--no-bridge` (stop after bundle, don't offer handoff), `--graph` / `--no-graph` (force-on / force-off the dynamic reference crawl — see Phase A.0), `--no-grill` (escape hatch: skip the design-tree interrogation that otherwise runs in greenfield and over clone ambiguities — see Phase A). **Feature-mode flags:** `--feature` (force brownfield mode), `--board <dir>` (target SPEC board; default the project's auto-detected `.claude/specs/backlog/`), `--epic <slug>` (epic name; else derived from the feature title).

**Budget semantics (quality-preserving):** `lean` uses the cheapest assigned model for deterministic/mechanical roles, one evaluator pass, and frontier escalation only for low-confidence multimodal or blocker findings; `balanced` uses the installed role map; `max` adds an independent critic for high-risk security/payment/migration decisions and low-confidence screenshot conclusions. All modes retain GATE 1, traceability, evaluator blocker handling, and GATE 2. Record the selected budget in `pipeline/00_meta.yaml`; do not silently downgrade a role after work begins.

**Depth default:** clone mode defaults to `--depth reference` (full visual + behavioural fit — turns on the per-screen fit checklist + the downstream `/<prefix> --fit` gate); greenfield defaults to `--depth production`. Override with `--depth`.

**Dynamic crawl auto-enable (clone only):** Phase A.0 runs when an `--apk` is supplied AND depth is `reference` AND a booted device is reachable — unless `--no-graph`. `--graph` forces the attempt (and asks for a device if none is found). It is always **additive**: if there is no device or the APK won't install/launch, log the reason and fall back to the static A-clone (user-provided screenshots) unchanged.

**Clone-mode validation** (reuse app-tdd-creator Step 0 verbatim): screenshots dir required & non-empty; ask for Play URL / APK if not given; reject `.aab/.apks/.xapk` with extraction hint. See `prompts/questions/clone.input.md`.

**Greenfield-mode validation:** no inputs needed; confirm the app idea is stated (if `/mp-spec --greenfield` with no description, ask for a one-paragraph idea first).

**Resolve `<APP>`:** `--name` → APK package stem → Play `id=` → screenshots folder → (greenfield) slugify the idea's working title.

## Step 1 — Bundle folder

Base: `<BASE>\<APP>\` (where `<BASE>` = `--base` or default personal folder). Layout:

```
<BASE>\<APP>\
├── input\
│   ├── screenshots\        (clone: normalized 01.png…NN.png — filled by the crawler when it runs)
│   ├── crawl\              (clone, --graph: trace.jsonl, states\STxx.png+xml, state-graph.json+.mmd, session.md)
│   ├── apk\ apk_decoded\ play_html\   (clone, as app-tdd-creator)
│   └── interview\          (greenfield: grill.md + stage1.yaml … stage5.yaml)
├── pipeline\               (raw agent outputs 01..07 + elicitation.md, grill.md (clone), eval_report.md)
│   ├── 00_meta.yaml
│   ├── cache\              (content-addressed input manifests + per-phase fingerprints)
│   ├── evidence\           (compact ID-based packets passed to specialist fan-outs)
│   └── user_answers_q*.yaml
└── spec\                   ← the shared bundle (what the bridge consumes)
    ├── 00_manifest.yaml
    ├── constitution.md       product-brief.md  requirements.md  user-stories.md
    ├── acceptance\*.feature  design.md  nfr.md  a11y.md  security-privacy.md
    ├── analytics.md  i18n.md  risks.md  estimate.md  traceability.csv
    ├── deviations.md          (clone: intended deviations from the reference — the fit gate suppresses these)
    ├── fit\<Sxx>.md  fit\registry.csv   (clone, depth ≥ reference: per-screen must-match checklists + screen↔reference registry)
    └── platform\android.md   platform\ios.md   (ios = populated stub unless --platforms includes ios)
```

Existence handling (`--fresh` / `--resume` / ask) — same as app-tdd-creator Step 1. Init `pipeline/00_meta.yaml` (app, mode, platforms, base, schema_version, phases_completed[], started_utc) and `spec/00_manifest.yaml` (see `prompts/templates/00_manifest.tmpl.yaml`).

### Content-addressed resume and cache (hard)

Resolve `scripts/spec-cache.sh` beside this skill and use it before every agent phase. Run
`fingerprint pipeline/cache <phase> <only the source inputs for that phase>`; then `check` the returned
fingerprint. A hit is reusable only when every declared output exists and validates against its schema.
On a miss, run the phase and call `record` only after its outputs validate. Never reuse by file existence
alone. Cache manifests are auditable evidence and stay under `pipeline/cache/`; they never include secrets,
credentials, decoded APK binaries, or generated outputs. `--fresh` bypasses hits but preserves prior cache
history; `--only-failed-rubrics` requires a matching upstream inventory fingerprint and otherwise falls back
to the normal owning-agent rerun.

Suggested phase inputs: intake = normalized screenshots/APK hash/Play snapshot/interview answers; inventory =
intake JSON + grill ledger; requirements = locked inventory + constitution; design = inventory + analyzer
facts; quality = compact evidence packet + posture; evaluator = validated artifact hashes. Include the prompt
library version IDs and model assignment in each fingerprint so a prompt/model upgrade invalidates only the
affected phase.

If `--dry-run` — print planned phases + gates, stop.

**Feature mode** builds **no** `spec/` bundle. It keeps working files under `<BASE>\<feature-slug>\pipeline\` (`grounding.md`, `grill.md`, `decomposition.json`) for resumability, and **emits the epic into the target project's board** (`--board`, default the grounded `.claude/specs/backlog/`). See Step F.

## Step 2 — Phase A: intake (mode-specific)

Print `⟳ Phase A — Сбор данных (<mode>)`.

### A.0-crawl (clone, optional — dynamic reference exploration)
Runs only under the auto-enable / `--graph` conditions above. Goal: replace hand-collected screenshots
with an **observed** corpus + a state graph, so the analyzers stop guessing. **You (the main session)
own the loop and the state files**; the work is split across three single-purpose sub-agents in
**separate sessions** — `crawl-navigator` (plans the next step), `crawl-executor` (drives the device),
`crawl-reviewer` (classifies the result + scores coverage). State lives only in files, so a killed run
resumes from them.

1. **Resolve the crawl scripts dir.** Use whichever exists: `${CLAUDE_PLUGIN_ROOT}/skills/mp-spec/scripts/crawl`
   (plugin) → `.codex/skills/mp-spec/scripts/crawl` (global install). Call it `$CRAWL`.
2. **Device pre-flight (you ask; sub-agents can't).** `bash "$CRAWL/device-preflight.sh"`. If `ok:false`,
   ask the user where/how the test device is connected (`Read prompt questions/clone.crawl-setup.md`) —
   adb path, serial, how connected — set `ADB`/`ANDROID_SERIAL` accordingly and retry. Record the working
   answer in `pipeline/00_meta.yaml` (`crawl.device{serial,w,h,android}`) so `--resume` never re-asks.
   If still no device and `--graph` was not explicit → skip A.0 (note `crawl.skipped:"no device"`), fall
   through to static A-clone.
3. **Consent + install + reset + init the graph.** First confirm the crawl **consent** and collect any
   optional **test credentials** (`Read prompt questions/clone.crawl-setup.md`): consent mode
   `seed`/`explore-only`/`decline`; hold credentials **in session only — never write them to any file**.
   Then `app-control.sh install <apk>` → `app-control.sh clear <package>` (once — deterministic
   first-run) → `app-control.sh launch <package>` (`package` from the apk-analyzer; run it first if
   needed). If install/launch fails → note `crawl.skipped:"<reason>"`, fall through to static A-clone.
   **Normalize the capture environment first** (so reference frames and the later `--fit` captures
   are pixel-comparable): fix the status bar via demo mode —
   `adb shell settings put global sysui_demo_allowed 1`, then
   `adb shell am broadcast -a com.android.systemui.demo -e command enter`,
   `… -e command clock -e hhmm 1000`, `… -e command battery -e level 100 -e plugged false`,
   `… -e command network -e wifi show -e level 4`, `… -e command notifications -e visible false`;
   plus `adb shell settings put system font_scale 1.0`. Record the AVD profile + density in
   `00_meta.yaml` (`crawl.device.density` via `adb shell wm density`) so `--fit` captures on the
   SAME profile. On finish: `… -e command exit` (best-effort — never block the crawl on demo mode).
   Capture the launch state (`screencap` + `ui-dump`), make it node `ST01` (`launch_state`), enumerate
   its frontier, and write the initial `input/crawl/state-graph.json`.
4. **The trio loop** (you drive it; persist after every step so `--resume` works). Repeat until a stop
   condition (below):
   a. **Navigate.** Call `crawl-navigator` with `{state_graph, coverage, budget}`. It returns one
      `goal` (or `{done:true}`). The goal `type` is `explore`, or — when consent is `seed` — `auth`
      (get past a sign-in wall) / `seed` (populate an empty state). On `done` → finalize. (If consent
      was `explore-only`, tell the navigator to emit explore goals only.)
   b. **Execute ⇄ Review** (inner loop, **max 2 retries** — mirror the Phase F evaluator-optimizer):
      - Call `crawl-executor` with `{goal, package, scripts_dir:$CRAWL, crawl_dir, state_graph, device,
        iter}` — and for an `auth` goal also pass `credentials` if the user provided them (runtime-only;
        do not persist). It relaunches, replays `goal.path`, performs the goal (explore: one affordance;
        auth: fill+submit the form; seed: create `count` synthetic entries), captures + dedups, and
        returns a result (`reached_target`, `goal_type`, `after`{new|known,data_state}, `dead_end`,
        `blocker` — `needs_human:…` on an OTP/captcha wall).
      - Call `crawl-reviewer` with `{goal, result, before_shot, coverage, retries_so_far}`. It returns
        `{edge_class, success_met, coverage_confidence, decision, critique, needs_seeding, needs_human}`.
      - `decision:continue` and retries < 2 → re-call the executor with `goal.critique = review.critique`.
        Else accept.
   c. **Merge** the accepted result into `state-graph.json`: add/refresh the `after` node (with its
      frontier), add the edge `{from:before_state, to:after.id, action, class:review.edge_class,
      confidence:1.0, source:"observed"}`, and move `goal.affordance` from the before-node's
      `frontier_remaining` → `tried` (or `blocked` on a guardrail). Bump `coverage{iters,states,actions}`.
   d. **Update `coverage.md`** (roots seen, states/iter trend, `coverage_confidence`, accumulated
      `needs_seeding[]` / `needs_human[]`) and append the iteration to `session.md`.
   **Stop** when: navigator says `done`; OR coverage plateaus (≥ K=4 iters added no new state); OR
   budget hit (`max_iters`/`max_states`/`max_actions`, defaults `40/25/60`). Surface `needs_human[]`
   briefly to the user.
5. **Finalize + cleanup.** For each unique node, copy its representative frame to `input/screenshots/`
   (`NN.png`, in node order) **and record `screenshot_file:"NN.png"` on the node** (this filename is the
   bridge that lets `navigation-flow-analyzer` map crawl `ST*` ids onto business `S*` screens — both
   reference the same image). **Distil the element manifests:**
   `bash "$CRAWL/element-manifest.sh" --states-dir input/crawl/states --out-dir input/crawl/elements`
   → one `ST*.json` per dump listing every interactive element (class / resource-id / text /
   content-desc / bounds). This is the deterministic "every button" ground truth: the evaluator's
   Class 5 audits the inventory against it and `--fit` later diffs the built app's element tree
   against it. **Then add exact dp metrics:** read the density recorded at capture
   (`crawl.device.density`, else `adb shell wm density` now) and run
   `bash "$CRAWL/bounds-to-dp.sh" --elements-dir input/crawl/elements --density <dpi>` — each
   element gains `bounds_dp`/`size_dp`, so the fit checklists can quote real numbers
   ("FAB 56×56dp") instead of density adjectives. Write `state-graph.mmd`. `app-control.sh stop <package>`. Set
   `crawl.completed:true` + coverage in `00_meta.yaml`. The observed corpus now feeds A-clone (below);
   `state-graph.json` feeds `navigation-flow-analyzer` (observed edges override its guesses).

### A-clone (reuse existing analyzer agents)
Run the app-tdd-creator fan-out **unchanged**:
1. Parallel: `play-store-scraper` (haiku), `screenshot-business-analyzer` (opus), `screenshot-style-analyzer` (opus), `apk-analyzer` (sonnet, if `--apk`). Merge JSON into `00_meta.yaml` with the same source-priority table (APK ground-truth wins palette/strings/manifest/permissions/SDKs/locales).
2. Sequential: `navigation-flow-analyzer` (sonnet) → `data-model-extractor` (sonnet).
Question batches A–E interleave exactly as app-tdd-creator does — `Read prompt questions/clone.batchA.md` … `clone.batchE.md`. Dynamic batch B from `ambiguities[]`.

**Grill the ambiguities (unless `--no-grill`).** When the analyzers return a non-empty `ambiguities[]` and/or `state_gaps[]`, resolve them with the design-tree interrogation instead of one flat batch: `Read prompt techniques/grill-me.md` (clone variant — input is the draft inventory + `ambiguities[]` + `state_gaps[]`). Walk them upstream-first (an ambiguity about a screen's purpose before one about a field on it), one question at a time, each with a recommended answer drawn from the analyzer evidence, and poke for unhandled states the screenshots never showed. Write the ledger to `pipeline/grill.md`; its resolved decisions close the ambiguities, and any deferred items flow into GATE 1 inventory notes + `risks.md` tagged `(assumption)`. This replaces the flat dynamic batch B when ambiguities exist; with none, the static batches run unchanged.

The business-analyzer also returns a per-screen `interactions[]` map (gestures / entry order / partial-vs-full overlays) and `state_gaps[]` (states the app has but that were not screenshotted). **Surface `state_gaps[]` in intake** and ask the user to capture the missing states (empty/loading/error) — a clone that never sees a state ships a wrong one (the empty-state class of divergence). The `interactions[]` map feeds the per-screen behaviour spec in `design.md` and the behavioural arm of `/<prefix> --fit`.

When **A.0-crawl ran**, `input/screenshots/` already holds the observed states, so `state_gaps[]` is typically near-empty — only ask the user for states the crawl could not reach (e.g. behind an auth wall it flagged `needs_human`). `input/crawl/state-graph.json` records the observed transitions; later phases consume it to upgrade `navigation-flow-analyzer` edges from inferred to `source:observed` (Phase 2 of the crawler work).

### A-green (staged interview elicitation)
Funnel: broad → narrow, each stage's answers constrain the next (anti-hallucination via propose-then-confirm).

**Stage 0 — Grill (design-tree interrogation, runs first; mandatory unless `--no-grill`).** Before the structured batches, run an adversarial **one-question-at-a-time** pass that resolves the idea as a *tree of decisions* — roots (audience / single core job / explicit out-of-scope) before the branches they constrain — and actively pokes holes (hidden assumptions, contradictions, unhandled states, scope creep). `Read prompt techniques/grill-me.md` and follow it literally; offer a recommended answer for every question. Run it **after** the idea paragraph is captured (the stage-1 pre-step) and write the resolved-decisions ledger to `input/interview/grill.md`. The five stages below then read that ledger: every candidate JTBD / screen / entity must trace to a grilled decision or the idea paragraph, deferred open-questions seed the owning stage, and "Out of scope" items are never proposed. Append `grill` to `phases_completed`. This is why greenfield no longer guesses on a thin idea — the grill establishes the upstream decisions first. The grill — and the five stages' recommended defaults after it — also reads the **cross-project user profile** (`$MP_USER_PROFILE` or `~/.config/mobile-pipeline/user-profile.md`) when it exists: profile facts (taste, language, process preferences accumulated across the user's projects) bias recommended answers and stage defaults but never auto-decide. The prompt's user-profile rule applies in every grill mode, including the clone ambiguity walk and the feature variant.

Then five batches via AskUserQuestion (≤4 Qs each), saved to `input/interview/stageN.yaml`:
1. `Read prompt questions/greenfield.stage1-vision.md` — idea, audience, platform(s), monetization.
2. `…stage2-inventory.md` — JTBD; model **proposes** a candidate screen list as options (each citing the stage-1 answer that drove it), user edits; user roles.
3. `…stage3-flows.md` — per top-3 screens: key actions, validation rules, empty/error states (dynamic, ≤3 batches).
4. `…stage4-data.md` — model proposes entities/relations, user prunes; auth; integrations; offline.
5. `…stage5-posture.md` — a11y target, locales, data sensitivity/consent, analytics goals.

### A-feature (brownfield — ground, grill, decompose)
For a feature added to an **existing** project. No analyzers and no interview stages — three sub-steps, then straight to Step F:
1. **Ground.** `Read prompt techniques/grounding.md`, then fan out read-only over the target repo → `pipeline/grounding.md` (verified `file:line` facts + the project's SPEC-board format). Every later `CHANGED_HINT` must cite a fact from here. **Run the fan-out via the cheap read-only `grounding-scout` subagent** — spawn ≤3 in parallel, one `focus` each (`"nav + entry points"`, `"domain/data signatures + conventions"`, `"SPEC-board format + test/CI gotchas"` with `want_spec_format:true`); each returns a JSON fact ledger and you (the orchestrator) own and assemble `grounding.md` from them — renumber the lanes' `G#` ids and keep the conclusions, not file dumps. This keeps grounding off the orchestrator's (expensive) model. **Fallback (portability):** if the harness can't spawn `grounding-scout`, do the same read-only fan-out inline (or via generic `Explore` subagents) — the ledger output is identical either way.
2. **Grill.** `Read prompt techniques/grill-me.md` (feature variant — input is the feature description + the grounding ledger) → `pipeline/grill.md`. Resolve the feature as a decision tree (ambiguity-scaled budget); the locked decisions become the epic's locked decisions.
3. **Decompose.** `Read prompt questions/feature.decompose.md` — propose the ordered, dependency-aware SPEC set (with same-file clash flags) and confirm it (**this is the feature-mode GATE 1**) → `pipeline/decomposition.json`.
Feature mode then SKIPS Steps 4–9 (the whole-app artifact pipeline + GATE 2) and goes to **Step F**.

## Step 3 — GATE 1: confirm inventory (human, hard stop)

Both modes produce a **feature inventory** (screens, features, roles, entities, integrations + per-item source & confidence). Validate against `prompts/schemas/feature-inventory.schema.json`. Print a compact table (low-confidence rows flagged) and call AskUserQuestion: всё верно / убрать лишнее / добавить недостающее / объединить дубликаты. **Nothing downstream runs until this is confirmed** — the locked inventory is the grounding for every artifact, so a wrong screen never propagates into 14 files. **Feature mode** uses the decomposition confirmation (`questions/feature.decompose.md`) as its GATE 1 — confirm the ordered SPEC set there, then branch to **Step F** (skipping Steps 4–9).

If a grill ledger exists (`input/interview/grill.md` or `pipeline/grill.md`), reconcile against it before printing: every inventory row should trace to a resolved decision (or analyzer/interview answer), no row may contradict an "Out of scope" entry, and carry the ledger's deferred open-questions into the table as flagged `(assumption)` rows so the user decides them here.

## Step 4 — Phase B: normalize to neutral inventory

Write the confirmed inventory to `pipeline/feature-inventory.json` (the neutral merge format). Clone derives it from analyzer JSON; greenfield from interview YAML. Everything C–F reads this — identical regardless of mode.

Then build `pipeline/evidence/core.json`: one compact, ID-based packet containing the locked inventory,
resolved decisions, source/provenance pointers, confidence, posture flags, and hashes/paths of larger
artifacts. Specialists receive this packet plus the ONE rubric they own; they do not receive the full chat,
raw file dumps, unrelated analyzer payloads, or other quality rubrics. Deduplicate equivalent facts before
assigning IDs. Keep large text/images on disk and pass paths + hashes + the minimum cited excerpt/crop.
Record each specialist with `scripts/spec-usage.sh pipeline/agent-usage.jsonl ...`. Prefer provider-reported
token counts; when unavailable, pass input/output character counts and let the script emit a clearly marked
estimate. Include phase, role, model, reasoning effort, duration, retry, cache hit, and one correlation ID.

## Step 5 — Phase C: requirements + stories + acceptance

1. `constitution-author` (haiku) → `spec/constitution.md` — `Read prompt templates/constitution.tmpl.md`. Generated **from** the target project's existing CLAUDE.md/memory when present (not a competing source of truth).
1b. Main session writes `spec/product-brief.md` (Product layer): problem, audience, UVP, competitors, success metrics, monetization — synthesised from `feature-inventory.json` + Q-batch/interview answers. This is the design's `product-brief-writer` aggregation step; no sub-agent.
2. `requirements-author` (sonnet, `source: analyzers|interview`) → `spec/requirements.md` (EARS `FR-NNN`) + neutral inventory enrichment. `Read prompt rubrics/ears-requirements.md`.
3. `user-story-writer` (sonnet) → `spec/user-stories.md` (`US-NNN`, each linking FR-IDs).
4. `acceptance-criteria-writer` (sonnet) → `spec/acceptance/*.feature` (UI-agnostic Gherkin). `Read prompt rubrics/gherkin-acceptance.md`.

> ID policy: prefer `US-x` + screen `ACn` + `BR-x` (already testable); `FR-x`/`NFR-x` EARS used for cross-cutting + greenfield. Do **not** force `FR-x` over existing story-level requirements.

## Step 6 — Phase D: design

`design-aggregator` (main session, no sub-agent — like app-tdd-creator Phase 4) writes:
- `spec/design.md` — **platform-neutral** body: overview, architecture, navigation graph, data model (neutral types), per-screen behaviour, business rules. `Read prompt templates/design.tmpl.md`.
- `spec/platform/android.md` — the **only** place Compose/Hilt/Room/gradle/minSdk/permissions appear. `Read prompt templates/platform.android.tmpl.md`.
- `spec/i18n.md` — via i18n sub-prompt (no separate agent).
- `spec/design-tokens.json` — **machine-readable design tokens** for direct theme generation
  downstream: the style-analyzer's JSON (palette, dark_palette, typography, spacing,
  corner_radius, elevation, icon_style) with apk-analyzer exact values overriding guesses
  (`exact_palette_*`, `exact_dimensions`, extracted font families) and a `provenance` field per
  group (`apk` | `screenshot-estimate`). The dev pipeline's ui-designer consumes this file
  verbatim — no manual Material Theme Builder seam for clones.
- `spec/platform/ios.md` — populated stub unless `--platforms` includes `ios`.

## Step 7 — Phase E: quality artifacts (parallel fan-out)

First write `pipeline/quality-plan.json` from the locked posture/risk flags. Every bundle still contains
every required quality artifact, but specialist calls are conditional and auditable:

- always run `nfr-analyzer`, `a11y-reviewer`, and `risk-estimator` (the latter writes both `risks.md` + `estimate.md`);
- run `security-privacy-reviewer` when the inventory contains authentication, sensitive/personal data,
  permissions, network/backend access, payments, sharing, or external SDKs; otherwise the main session
  renders the rubric's explicit low-risk/not-applicable artifact without inventing threats;
- run `analytics-taxonomy-designer` when analytics is requested or an analytics SDK/event requirement is
  present; otherwise render an explicit `analytics: disabled` artifact with the decision provenance;
- under `--budget max`, add an independent critic only for high-risk security/payment/migration decisions;
  under `lean`, mechanical roles use the cheapest installed tier and escalate on low confidence/blockers.

Fan out the selected specialists in one message. Each reads `pipeline/evidence/core.json` + the ONE relevant
rubric, writes its artifact, and returns compact JSON. Persist the chosen/skipped roles and reasons in
`quality-plan.json`; a skipped call never means a missing artifact.

**Clone mode, depth ≥ reference:** also fan out `fit-checklist-author` (opus, multimodal) → `spec/fit/<Sxx>.md` (per-screen visual + behavioural must-match checklists, each grounded in its reference screenshot), `spec/fit/registry.csv` (screen ↔ reference image ↔ FR/AC), and a `spec/deviations.md` stub (intended deviations from the reference). This is the contract the build-time `/<prefix> --fit` gate later checks the running app against — so the clone converges to the reference instead of drifting (the failure mode that produced the 7 MyMoney↔Monefy divergences).

**When A.0-crawl ran**, also pass `crawl_graph` (`input/crawl/state-graph.json`) + `crawl_states_dir` (`input/crawl/states/`) + `crawl_elements_dir` (`input/crawl/elements/`, when present) to `fit-checklist-author`. It then grounds the checklist in the **observed per-state frames** — including the `data_state:"filled"` states the seed goals produced — emits a `registry.csv` row per (screen, captured state), and merges the per-state element manifests into `spec/fit/elements/<Sxx>.json` (one per screen — the union of its states' interactive elements), so `--fit` drives the built app into each state (empty *and* filled), compares it against its own real reference frame, AND diffs the built element tree against the screen's manifest (a missing button is caught deterministically). This is the payoff of the dynamic crawl: the fit contract is anchored to states the reference app actually showed, not a partial hand-captured set.

## Step 8 — Phase F: evaluate (evaluator-optimizer) + traceability

0. Run `scripts/spec-preflight.sh spec [--clone] --out pipeline/eval-preflight.json` first. A
   mechanical failure goes directly to the owning artifact; do not spend a frontier critic call explaining
   malformed JSON, duplicate IDs, broken references, or missing required files.
1. `spec-evaluator` (opus, **read-only**) → `spec/traceability.csv` + `pipeline/eval_report.md`. `Read prompt rubrics/evaluator-rubric.md`. Pass `pipeline/evidence/core.json`, artifact hashes, and preflight results — not raw chat/history. Five check classes: cross-artifact consistency / grounding (no ungrounded requirement) / completeness / constitution contradictions / **affordance coverage** (clone, when `input/crawl/elements/` or `spec/fit/elements/` exists — every interactive element observed in the reference maps to an inventory feature/CTA or an explicit decision; unmatched = blocker). In **clone mode** the evaluator runs clone-strict: `orphan_screen` and `state_coverage_gap` escalate warn → blocker. Returns `{verdict, findings[], coverage, checked_classes[], confidence}`.
2. **Disagreement gate:** when two analyzers disagree on a high-impact fact, or a screenshot conclusion
   that drives navigation/business rules remains low-confidence, request one independent focused opinion on
   that fact only. Record both claims, evidence, and the reconciled decision; never rerun the entire analyzer.
3. **Optimize loop:** on any `blocker` finding, re-invoke **only the owning agent(s)** (parsed from `finding.artifact`) with the failed check classes + findings as input. **Max 2 retries.** With `--only-failed-rubrics`, verify that upstream hashes match, then run exactly this targeted path. Still failing → stop, show residual blockers, ask the user for guidance (mirror `/cmp` Step 4 behaviour). `warn`/`info` never block — they land in `risks.md` / design open-questions tagged `(assumption)`.

## Step 9 — GATE 2: final acceptance (human)

On `pass`, print the verdict summary + coverage stats + warnings — **and, as explicit numbered
lists the user must see (never leave them buried in agent JSON):** `coverage.fr_without_coverage`
+ `story_without_scenario` + `state_coverage_gaps` (evaluator), `coverage_gaps[]`
(user-story-writer), `stories_without_scenario[]` / `untestable_stories[]`
(acceptance-criteria-writer), and `screens_uncovered[]` + `low_confidence_maps[]`
(fit-checklist-author, clone). Empty lists → one line "покрытие полное". Then AskUserQuestion:
принять и передать в разработку / внести правки / принять с зафиксированными рисками —
acceptance explicitly covers the printed gaps (they are the items most likely to become a
forgotten feature downstream). Only on accept set `00_manifest.yaml: evaluator_verdict: pass`
and continue.

## Step F — Feature mode: emit the backlog epic (replaces Steps 4–9)

Reached from A-feature once the decomposition is confirmed. Emit, into `--board` (default the grounded `.claude/specs/backlog/`), the epic as **project-native** SPEC files — main session, **no sub-agent** (portable across Claude/Codex):

1. **Overview** — `Read prompt templates/feature-epic-overview.tmpl.md` → `<board>/<epic>-00-overview.md` (goal, locked decisions from `grill.md`, the SPEC table from `decomposition.json`, key verified facts from `grounding.md`). **Match the project's house format** captured in `grounding.md`.
2. **Numbered SPECs** — for each entry in `decomposition.json`, `Read prompt templates/feature-spec.tmpl.md` → `<board>/<epic>-NN-<slug>.md`. Every `CHANGED_HINT` cites a grounding `G#` (or `(assumption)`); add per-SPEC Gherkin acceptance (`rubrics/gherkin-acceptance`); for a `domain_math` SPEC include a Calculation block (`rubrics/domain-math`); record same-file clashes in CONSTRAINTS.
3. **Light eval (reuse `spec-evaluator`, read-only, adapted).** Check cross-SPEC consistency, grounding (no ungrounded `CHANGED_HINT`), and same-file-clash sequencing. On a `blocker`, fix the owning SPEC (**max 2 retries**), then proceed; `warn`/`info` → `(assumption)`-tagged notes in the overview.

Feature mode writes **no** `spec/` bundle and has **no** GATE 2. Then continue to Step 10 (handoff).

## Step 10 — Handoff (auto-bridge)

Unless `--no-bridge`: tell the user the bundle is ready and how to hand it off to their dev pipeline. If the project ships a **spec-bridge** (e.g. MyMoney's `cmp-planner-android`, invoked as `/<prefix> --plan <bundle>`, which turns the bundle into the project's plan files behind a `y/d/n` gate), name it and print the command. Otherwise the **portable handoff is the bundle itself**: `traceability.csv` + `design.md` + `acceptance/*.feature` feed any coding pipeline (e.g. `/<prefix> --feature` per epic). Always print the bundle path.

**Feature mode handoff.** Print the epic path + the SPEC count, and the board command — `/<prefix> --feature --next` (implements the backlog SPECs in Order; e.g. MyMoney's `/mp --feature --next`). No bundle, no fit-loop.

**Clone fit loop.** For a clone bundle (depth ≥ reference), tell the user that after the dev pipeline implements the screens they should run `/<prefix> --fit` to compare the built app against the reference screenshots — the bundle's `fit/` checklists + `deviations.md` drive that gate, and each unexplained divergence becomes a backlog SPEC to fix, closing the clone loop. **Also print the token handoff step:** copy `spec/design-tokens.json` into the dev project as `.claude/mp/design-tokens.json` — the project's ui-designer then generates `Color.kt`/`Type.kt` from the exact reference tokens instead of a Theme Builder guess (and `spec/assets/`, when the apk-analyzer extracted them, can be reused per its manifest's legal note).

## Step 11 — Report

Open the bundle folder (`Start-Process explorer.exe "<BASE>\<APP>"`). Final Russian summary: bundle path, mode, screen/feature/entity counts, artifact list with line counts, evaluator verdict + coverage, and the handoff command. The per-agent usage table comes from `pipeline/agent-usage.jsonl` and reports model, reasoning effort, actual input/output/cached/reasoning tokens when the harness exposes them, fallback char-based estimates clearly marked `estimated`, duration, retries, cache hit, and correlation ID. Include workflow totals plus `tokens per accepted FR/US`; never present an estimate as provider-billed usage.

**Feature mode:** no bundle folder to open — summarise the epic instead: board path, epic slug, SPEC count + titles, grounding-fact count, residual `(assumption)` items, and the `/<prefix> --feature --next` command.

## Edge cases

- Never write code/tests. Never delete user files (list paths instead). Clone/greenfield write only under `<BASE>\<APP>\`. **Feature mode** additionally writes SPEC files into the target project's `--board` (its whole purpose) + working files under `<BASE>\<feature-slug>\pipeline\` — but it must never overwrite or delete an existing SPEC (new files only; on a name collision, ask).
- Any agent fails 3× → note in meta, continue if possible.
- `screenshots_count == 1` → MVP depth. `> 50` → warn (opus cost) before business-analyzer, offer subset.
- Play/Chrome MCP unavailable, APK undecodable, invalid APK → same fallbacks as app-tdd-creator Step 0/3.
- Greenfield with a thin idea → ask one clarifying paragraph before stage 1; never invent the product.

## Mode hint footer

Append to `spec/design.md`:
```markdown
---
*Сгенерировано `/mp-spec` (mode `<mode>`, depth `<depth>`, platforms `<list>`).*
*Хендофф в разработку: `/<prefix> --plan <BASE>/<APP>/spec` (если у проекта есть spec-мост; иначе бандл портативен).*
```
