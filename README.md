# claude-mobile-pipeline (cmp)

Reusable Claude Code agent pipeline for mobile projects (Android + iOS), with shared
workflow (`/discuss`, `/feature`, `/bugfix`, `/tdd`) and platform-specific specialists.

Battle-tested origin: extracted from a 6-iteration `diet_helper` Android project (Kotlin +
Compose + Hilt + Room) where the pattern was refined through real shipped features.

## The main pipelines

Everyday work runs through **two plugin commands** — `/mp-spec` (build the spec) and `/mp`
(build the app). They compose into five end-to-end pipelines. Both come from the
`mobile-pipeline` marketplace below; enable it in your project first, then:

| # | Pipeline | How to run | Output |
|---|----------|------------|--------|
| **1** | **Plan from an APK reference** — implementation plan with phases | `/mp-spec <screenshots/> --apk app.apk --play <play_url>` → `/mp --plan --phases --bootstrap --from <bundle>/spec` | `spec/` bundle + per-screen fit checklist, then numbered `docs/implementation_plan/PHASE_NN_*.md` |
| **2** | **Execute the phases, one task at a time** | `/mp --phase` (repeat) · `/mp --check` to validate · `/mp --fit` (clone gate) | One task per run: SPEC → develop → review → test → verify, ticked in `PROGRESS.md` |
| **3** | **Spec from a brief (ТЗ) + fill the backlog** | `/mp-spec --greenfield` → `/mp --plan <epic-slug> --from <bundle>/spec` | `spec/` bundle from interview, then ordered SPECs on the `.claude/specs/backlog/` board |
| **4** | **Execute the backlog SPECs** | `/mp --feature --next` (repeat) · `/mp --feature --next --chain` (Codex conveyor) · or `/mp --feature --backlog <slug>` | Each SPEC promoted `backlog → active → done` through the full develop→verify→push chain; `--chain` starts the next local Codex task after a successful close |
| **5** | **Spec a feature into an existing app's backlog** (brownfield, one step) | `/mp-spec --feature "<feature>"` → `/mp --feature --next` | Grounds in the live codebase, grills the ambiguities, decomposes → an epic of ordered SPECs straight onto `.claude/specs/backlog/` — **no** `spec/` bundle, **no** `/mp --plan` bridge |

**1 → 2** is the heavy *clone* loop (reference fit is a verifiable gate — see
`docs/CLONE-PLAYBOOK.md`). **3 → 4** is the lighter *greenfield* loop (a resumable backlog
board for ad-hoc, independently-shippable features). **5 → 4** is the *brownfield* loop: it
skips the heavyweight `spec/` bundle and authors backlog SPECs directly from a feature
description against an existing project — the fastest front-door to the same row-4 executor.
The three coexist — pick the phase model for a full app build, the backlog (greenfield bundle
*or* brownfield direct) for individual features.

> **Two different `--feature` flags — don't confuse them.** `/mp-spec --feature` *authors*
> backlog SPECs (pipeline 5, the spec tool); `/mp --feature` *executes* a SPEC already on the
> board (pipeline 4, the dev orchestrator). They share the word but live on different commands.
> `/mp-spec --feature` also auto-engages when you invoke the spec tool from inside a project
> that already has a `.claude/specs/` board and pass a feature description with no clone inputs
> (`--board <dir>` / `--epic <slug>` override the target board and epic slug).

> `/mp-spec` and `/mp` are the marketplace-plugin commands. If you bootstrapped a per-project
> pipeline with a custom `--prefix` instead (see Quick start), the dev command is `/<prefix>`
> with the same flags (`--plan --phases`, `--phase`, `--feature --next`, …). The spec tool is
> also installable globally as `/app-spec-creator` via `install-spec.sh` (see Two halves).

## Marketplace (plugins) — recommended for reuse across projects

Instead of copying a pipeline into every project with `bootstrap.sh`, cmp is also a **multi-harness
plugin marketplace** named `mobile-pipeline` (`.claude-plugin/marketplace.json` for Claude,
`.agents/plugins/marketplace.json` for Codex). It ships two plugins you enable per project — edit
once here, regenerate, every project picks it up:

| Plugin | Command | What |
|--------|---------|------|
| `mp-spec` | `/mp-spec` | Spec-bundle creator (was `app-spec-creator`) + 22 analysis sub-agents |
| `mp-dev`  | `/mp`     | Dev orchestrator + specialist agents (Android) — Clean Arch, TDD, review/test/verify |

**Enable in a project** — add to its `.claude/settings.json`:

```json
{
  "extraKnownMarketplaces": {
    "mobile-pipeline": { "source": { "source": "github", "repo": "desvingns/mobile-pipeline" } }
  },
  "enabledPlugins": { "mp-spec@mobile-pipeline": true, "mp-dev@mobile-pipeline": true }
}
```

Project specifics for `mp-dev` live in **`.claude/mp/config.json`** (`package`, `packagePath`,
`platforms`, `sourceRoot`, `stack`, `uiLang`, `projectName`) + optional
**`.claude/mp/extras/<agent>.md`** overrides — the generic plugin agents read them at runtime.
After editing `templates/`, regenerate the plugin trees with `./lib/build-marketplace.sh`.

Notes: this uses the portable `github` source (`desvingns/mobile-pipeline`) — pull updates with
`claude plugin marketplace update mobile-pipeline`. A local `directory` source (`{"source":"directory",
"path":"D:\\Pet\\mobile-pipeline"}`) also works for offline development. Codex gets the `mp-spec`
and `mp-dev` **skills** via `codex-plugins/`; native `.codex/agents/*.toml` sub-agent shims still
install per-project because Codex plugins carry skills, not sub-agents. Full guide:
`docs/MARKETPLACE.md`.

## What you get

Run `bootstrap.sh` in any new mobile project and you get:

- **Orchestrator command** `/<prefix>` with workflows: `--discuss`, `--feature` (default and
  `--tdd`), `--bugfix`, `--coverage` (Android, diagnostic).
- **Specialist agents**: architect (brainstorm), developer (per platform), reviewer (Clean
  Arch + design-system + test hygiene), tester (per platform — with Mandatory Coverage
  Rules), runner (per platform — with lint + JaCoCo threshold), verifier (per platform —
  with tests-exist check), docs (STATE/DOC/CLAUDE keeper), coverage (Android, opt-in).
- **Live state files** at the project root: `STATE.md` (current), `ROADMAP.md` (planned),
  `DOCUMENTATION.md` (history) — automatically maintained by the `docs` agent.
- **Cross-session memory** at `~/.claude/projects/<sanitized>/memory/` — preferences,
  traps, conventions that survive across sessions.
- **Brainstorm artifacts** at `.claude/specs/` — persistent records of `--discuss` runs.
- **Test-discipline guarantees** (1.1+) — every new production class lands with a dedicated
  test file; reviewer blocks the chain on disabled/empty/sleep-based tests; runner enforces
  a configurable JaCoCo coverage threshold; verifier blocks push on missing-test gaps.

## Supported platforms

| Platform | Status | Stack assumptions |
|----------|--------|-------------------|
| Android  | Stable | Kotlin · Compose · Hilt · Room · Robolectric · Roborazzi |
| iOS      | Stubs (v1.0) — workable starting point, fill in for your stack | SwiftUI · Combine · XCTest · ViewInspector · snapshot-testing-swift |
| Flutter / React Native | Not yet — see `docs/ADDING-PLATFORM.md` for how to extend | — |

Single-platform projects: pass `--platform=android` or `--platform=ios`. Cross-platform
(shared workflow over both targets): `--platform=android,ios`.

## Two halves

cmp ships two independent tools that can be used together or separately:

1. **Per-project dev pipeline** (`bootstrap.sh`) — the original cmp. Run once per project to
   install a `/<prefix>` orchestrator + specialist agents (architect, developer, reviewer,
   tester, runner, verifier) into `.claude/` / `.codex/`. See below.

2. **Global spec-creation tool** (`install-spec.sh`) — added in v1.3. Run once per machine to
   install `app-spec-creator` globally into `~/.claude/` and/or `~/.codex/`. Takes an app
   idea or screenshots of an existing app and produces a complete, traceable `spec/` bundle
   (EARS requirements, user stories, Gherkin acceptance criteria, platform-neutral design,
   NFR/a11y/security/analytics/risks/estimate, traceability matrix) with two human gates and
   an evaluator-optimizer critic. See `docs/SPEC-PIPELINE.md` for the full guide.

```bash
# Install the spec tool once (both Claude Code and Codex CLI)
./install-spec.sh

# Then from any session:
# /app-spec-creator --greenfield   (brand-new app — interview mode)
# /app-spec-creator ./screenshots  (clone an existing app)
```

---

## Quick start

```bash
# Android, Russian UI, with custom prefix
bash /path/to/claude-mobile-pipeline/bootstrap.sh \
    --platform=android \
    --prefix=ft \
    --project-name="Fitness Tracker" \
    --package=com.example.fitness \
    --ui-lang=ru

# iOS minimal (stubs — you'll need to flesh out the agent prompts)
bash /path/to/claude-mobile-pipeline/bootstrap.sh \
    --platform=ios \
    --prefix=cn \
    --project-name="Cookbook Notes"

# Cross-platform shared workflow
bash /path/to/claude-mobile-pipeline/bootstrap.sh \
    --platform=android,ios \
    --prefix=mt \
    --project-name="Memo Time" \
    --package=com.example.memo
```

After bootstrap: edit `ROADMAP.md` to add Iteration 1, then run `/<prefix> --discuss <topic>`
in Claude Code to start.

## Docs

- `docs/USAGE.md` — full `bootstrap.sh` flags, examples for each platform
- `docs/ARCHITECTURE.md` — agent graph, how context flows between agents, why each layer exists
- `docs/OPTIMIZATION.md` — measured token savings, risk/model routing, cache/evidence strategy,
  telemetry, and memory/second-brain boundaries
- `docs/BRAIN-INTEGRATION.md` — inbox-only writes, bounded retrieval, provenance and promotion receipts
- `docs/SPEC-PIPELINE.md` — spec tool: `install-spec.sh`, the `spec/` bundle, 22 agents, intake modes, dual-harness, handoff
- `docs/CLONE-PLAYBOOK.md` — the clone loop (pipelines 1→2): reference → spec → phases → build → fit → fix
- `docs/CUSTOMIZATION.md` — how to adapt templates for your stack (different DI / DB / test framework)
- `docs/UPGRADE.md` — how to pull cmp improvements into an existing project (`--upgrade` flow)
- `docs/ADDING-PLATFORM.md` — how to add a new platform (Flutter, React Native) to cmp
- `docs/local-llm/` — design notes for delegating shaped/mechanical subtasks to a small
  local LLM (≤6 GB VRAM). Not implemented yet — these are the trade-off analysis for a
  future iteration.

## Versioning

This repo follows [SemVer](https://semver.org/):

- **PATCH** — wording fixes, typos (safe to auto-merge into existing projects)
- **MINOR** — new agents, optional sections (review before merging into existing projects)
- **MAJOR** — breaking changes (renames, JSON shape changes between agents)

Current version: see `VERSION`. Each bootstrap stamps `.claude/.cmp-version` into the target
project so future upgrades know where to start the diff.

## License

[Choose your license — recommended: MIT for templates]
