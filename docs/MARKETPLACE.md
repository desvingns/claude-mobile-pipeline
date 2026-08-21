# MARKETPLACE — `mobile-pipeline` plugin marketplace

cmp can be consumed as a **multi-harness plugin marketplace** (modelled on the proven
`ai-team-bootstrap` pattern) instead of copy-per-project via `bootstrap.sh`. One canonical source in
`templates/`, emitted into committed plugin trees, enabled per project. Edit once → regenerate →
every project picks it up.

## What ships

| Plugin | Slash | Harness | Contents |
|--------|-------|---------|----------|
| `mp-spec` | `/mp-spec` | Claude (skill + agents), Codex (skill only) | Spec-bundle creator (renamed from `app-spec-creator`) + 22 analysis sub-agents |
| `mp-dev`  | `/mp`     | Claude (command + agents + scripts), Codex (skill only) | Dev orchestrator + specialist agents (architect, developer, reviewer, tester, runner, verifier, docs, ...) + deterministic scripts |

**Why Codex differs:** Claude plugins can carry sub-agents (`agents/`); Codex plugins carry only
`skills`/`.mcp.json`/`.app.json`. So Codex gets the `mp-spec` and `mp-dev` *skills* via the
marketplace, but the sub-agent roster (`.codex/agents/*.toml`) is installed **per project** (via
`install-spec.sh` for spec; via the `templates/dev/codex/agent.toml.tmpl` shim contract for dev).

## Layout

```
mobile-pipeline/                          # this repo (rename optional — see bottom)
├── .claude-plugin/marketplace.json       # Claude marketplace catalog
├── .agents/plugins/marketplace.json      # Codex marketplace catalog
├── claude-plugins/
│   ├── mp-spec/{.claude-plugin/plugin.json, skills/mp-spec/{SKILL.md,prompts/}, agents/*.md}
│   └── mp-dev/{.claude-plugin/plugin.json, commands/{mp.md,mp-runtime/}, agents/mp-*.md, scripts/mp-*.sh}
├── codex-plugins/
│   ├── mp-spec/{.codex-plugin/plugin.json, skills/mp-spec/{SKILL.md,prompts/}}
│   └── mp-dev/{.codex-plugin/plugin.json, skills/mp-dev/{SKILL.md,references/}}
├── templates/                            # CANONICAL source (unchanged; bootstrap.sh still uses it)
└── lib/build-marketplace.sh              # generator: templates/ → plugin trees
```

## Enable in a project (Claude)

Add to the project's `.claude/settings.json` (merge with existing keys):

```json
{
  "extraKnownMarketplaces": {
    "mobile-pipeline": { "source": { "source": "directory", "path": "D:\\Pet\\claude-mobile-pipeline" } }
  },
  "enabledPlugins": { "mp-spec@mobile-pipeline": true, "mp-dev@mobile-pipeline": true }
}
```

Then in a Claude Code session: `/plugin` → confirm `mp-spec` / `mp-dev` are enabled → use `/mp-spec`
and `/mp`. (Or register globally once: `claude plugin marketplace add <path>`.)

> The `directory` source is **machine-local**. After you `git push` this repo to a remote, swap it
> for a portable git source:
> ```json
> "mobile-pipeline": { "source": { "source": "git", "url": "https://…/mobile-pipeline.git" }, "autoUpdate": true }
> ```

## Enable in a project (Codex)

```bash
codex plugin marketplace add /d/Pet/claude-mobile-pipeline   # or the git URL
codex plugin add mp-spec@mobile-pipeline
codex plugin add mp-dev@mobile-pipeline
```
Codex sub-agents (spec): `./install-spec.sh --harness codex` writes `~/.codex/agents/*.toml` +
`[agents]` config (needs `max_threads >= 6`). Generated spec agents pin explicit Codex model tiers
(`gpt-5.4-mini` for simple/mechanical roles, `gpt-5.4` for standard authoring/analysis, `gpt-5.6`
for screenshot/evaluator-critical roles) instead of inheriting the parent session.

Codex sub-agents (dev): the `mp-dev` Codex plugin provides the `$mp`/`/mp` skill bridge plus
`skills/mp-dev/references/codex-agent-shims.md`. Projects still install the 21 native
`.codex/agents/mp-*.toml` wrappers locally, using `templates/dev/codex/agent.toml.tmpl` and
`templates/dev/codex/config-fragment.toml`. The wrappers read the canonical Claude `mp-dev` agent
bodies from the plugin cache and then `.claude/mp/extras/<agent>.md`, so Claude and Codex share the
same project-specific overrides.

For a backlog conveyor in Codex, invoke `$mp --feature --next --chain`. It preserves `--next`'s
active-first selection and, after a successful SPEC close, creates one fresh **local,
same-project** Codex task with an empty conversation for the next runnable SPEC. The new task does
not inherit the previous turns, create a worktree, or create a Git branch; the hand-off only runs
from `main`. Existing verifier, epic-close, push, and human gates still stop the conveyor.

## `mp-dev` runtime config (per project)

The plugin agents are project-agnostic; project facts are read at runtime from
**`.claude/mp/config.json`**:

```json
{
  "projectName": "MyMoney",
  "package": "com.kshavrin.mymoney",
  "packagePath": "com/kshavrin/mymoney",
  "platforms": ["android"],
  "sourceRoot": "app/src/main/java/com/kshavrin/mymoney",
  "stack": "Kotlin · Compose Material3 · Hilt · Room · …",
  "uiLang": "en",
  "coverageTargetPct": 0,
  "docsAgent": "inert",
  "reviewerMode": "enforce",
  "acceptanceCellBudget": 24
}
```

| key | effect |
|---|---|
| `coverageTargetPct` | line-coverage floor for the full runner; `0` disables it (use when the project has its own per-module kover/jacoco gate) |
| `docsAgent` | `"inert"` skips the docs step entirely instead of paying an agent spawn to write nothing |
| `reviewerMode` | `"enforce"` (default) or `"warn-only"`. In `warn-only` the orchestrator passes `--warn-only` to the deterministic reviewer, so findings arrive under `warnings` with `by_check` counts and do not block. Intended for adopting checks a codebase has never run against — sizing the backlog first, then switching to `enforce`. |
| `acceptanceCellBudget` | maximum acceptance cells (the product of the SPEC's `Acceptance-matrix:` dimensions) before `{{PREFIX}}-spec-complexity.sh` recommends splitting the SPEC. Default `24`. Raise it only if your slices genuinely converge at a larger surface — the number is a review-cycle budget, not a style preference. |

`sourceRoot` describes the single-module layout. The deterministic reviewer resolves layers from
the path (`domain/`, `data/`, `presentation/`, `ui/` components, or a `feature/*` module), so a
multi-module project needs no extra configuration.

Optional per-agent overrides go in **`.claude/mp/extras/<agent-name>.md`** (e.g.
`.claude/mp/extras/mp-developer-android.md`). Each agent reads its extras file *after* its body;
extras win on conflict. (This generalizes MyMoney_app's old `cmp-mymoney/*-extras.md` layer.)

## Regenerate after editing `templates/`

```bash
./lib/build-marketplace.sh           # emits claude-plugins/ + codex-plugins/
./lib/build-marketplace.sh --dry-run # preview
```
Transforms applied for `mp-dev`: `{{PREFIX}}`→`mp`; `{{PACKAGE}}`/`{{PACKAGE_PATH}}`→`<package>`/
`<pkg-path>` tokens; `{{PROJECT_NAME}}`→"the project"; `.claude/scripts/`→`${CLAUDE_PLUGIN_ROOT}/scripts/`;
`.claude/.cmp-version`→`.claude/mp/config.json`; `platform:`→android; a config-read preamble injected
after each agent's frontmatter. `bootstrap.sh` and `templates/**/scripts/*.sh` are never edited
(codex-owned; legacy bootstrap stays byte-compatible). Validate: `claude plugin validate .`.

**CI safety net (stage 4):** `.github/workflows/regen-plugins.yml` regenerates + commits the
plugin trees automatically when `templates/` (or the generator/render engine) changes on `main`
— so a merged improvement propagates to every git-source consumer without anyone remembering
this step. PRs are still gated by the validate-plugins drift check, so the bot commit is
normally a no-op; it exists for direct pushes. Loop-guarded via the workflow's `paths` filter
(the bot commit touches only the generated trees).

## Manual cleanup of superseded local copies (do AFTER confirming `/mp` + `/mp-spec` work)

Per the never-delete rule these were left in place; remove them yourself once the plugins are
verified, so you don't run two divergent copies. Names differ (`cmp-*`/`dh-*` vs plugin `mp-*`) so
they coexist harmlessly until you remove them.

**MyMoney_app** (`D:\Pet\TDD_creater\MyMoney_app`):
- Remove generic locals now provided by the plugin: `.claude/agents/cmp-architect.md`,
  `cmp-docs.md`, `cmp-developer-android.md`, `cmp-reviewer-android.md`, `cmp-runner-android.md`,
  `cmp-runner-instrumented-android.md`, `cmp-tester-android.md`, `cmp-verifier-android.md`.
- Remove the old extras dir `.claude/cmp-mymoney/` (migrated to `.claude/mp/extras/`).
- **Keep** `.claude/agents/cmp-planner-android.md`, `selfimprove-retro.md`, and `.claude/commands/cmp.md`
  for the MyMoney-specific `--phase`/`--check`/`--device`/`--plan` flows (not in the generic plugin).

**diet_helper** (`D:\diet_helper`):
- Remove generic locals: `.claude/agents/{dh-architect,dh-developer,dh-docs,dh-reviewer,dh-runner,dh-tester,dh-verifier,dh-coverage}.md`,
  `.claude/scripts/{dh-runner.sh,dh-reviewer.sh}`, `.claude/commands/dh.md`.
- Remove the PowerShell commands `.claude/commands/build.md` + `.claude/commands/test.md`
  (**golden-rule violation** — PowerShell; superseded by the deterministic bash scripts in `/mp`).
- **Keep** `.claude/agents/{dh-intake,dh-knowledge}.md` + `selfimprove-retro.md` until their behaviour
  is folded into the plugin (see Follow-ups).

**Old global spec install** (if you ever ran `install-spec.sh` for Claude): remove
`~/.claude/skills/app-spec-creator` + the 22 `~/.claude/agents/<spec-agent>.md` to avoid duplicate
names with the `mp-spec` plugin.

## Improvement workflow (downstream project → mobile-pipeline PR)

The pipeline improves itself through one loop, with a clear split between *project-local* lessons and
*plugin-level* improvements:

1. **Observe / reflect** — the existing `selfimprove/` kit (per project) captures runs and reflects;
   after a `/mp` ship the orchestrator may spawn **`mp-knowledge`** with the SPEC + changed files + a
   session recap.
2. **Route** — `mp-knowledge` classifies each lesson:
   - **PROJECT-LOCAL** (true only for this app) → it writes the project's memory and/or
     `.claude/mp/extras/<agent>.md`. Nothing leaves the project.
   - **PLUGIN-LEVEL** (would help *every* project — a wrong/missing rule in a generic `mp-*` agent or
     the orchestrator) → it returns `plugin_improvements[]`, and the orchestrator offers `/mp --improve`.
3. **Draft** — `/mp --improve` spawns **`mp-improve`** (read-only on the plugin): it locates the
   mobile-pipeline working copy (from `extraKnownMarketplaces.mobile-pipeline.source.path` or `$MP_REPO`),
   finds the exact **canonical** file under `templates/`, and stages a minimal patch + a change-log
   entry under `mobile-pipeline/.ai/proposals/<slug>.*` (verified with `git apply --check`).
4. **Gate → PR** — only after the user answers `y`, `scripts/mp-propose-improvement.sh` runs:
   branch `improve/<slug>` → apply the patch to `templates/` → `./lib/build-marketplace.sh` (regenerate
   the plugin trees) → commit → push → open a PR via `gh`. Review + merge happens on GitHub; once merged
   to the default branch, every project picks it up on the next `/plugin marketplace update`.

**Guarantees:** the live plugin copy is read-only; the downstream project's source is never touched;
mobile-pipeline changes only through a reviewed PR (never a silent push); patches edit only `templates/`
(never the generated trees), so the one-source discipline holds.

### Batch, cross-project & CI (v1.4.0)

- **Queue + batch** — `mp-knowledge` / `mp-reflect` *stage* proposals to `mobile-pipeline/.ai/proposals/`
  (the queue) rather than PR each. `/mp --improve --drain` aggregates the whole queue into **one** PR
  (`improve/batch-<stamp>`, regenerated once) via `scripts/mp-improve-drain.sh`. A deliberate
  `/mp --improve "<note>"` stays a **separate** single PR (`scripts/mp-propose-improvement.sh`).
- **Cross-project reflection** — `/mp --reflect` runs `scripts/mp-cross-reflect.sh`, which aggregates each
  project's `selfimprove/lessons.md` + retro notes (projects listed in `~/.config/mobile-pipeline/projects.txt`)
  into a digest flagging keywords recurring in **≥2 projects**; the `mp-reflect` agent then queues
  proposals only for genuinely general patterns. Drain them with `--improve --drain`.
- **CI gate** — `.github/workflows/validate-plugins.yml` runs on every PR (incl. the auto-opened
  `improve/*` PRs): JSON-manifest validity, `bash -n` over lib/templates/plugins/selfimprove/eval +
  the installers, `shellcheck -S error`, placeholder/marker leak check, and a **regeneration-drift**
  check (`./lib/build-marketplace.sh` then `git diff` must be empty — enforces the one-source
  discipline so nobody hand-edits the generated trees or forgets to regenerate). On `main`,
  `regen-plugins.yml` additionally auto-regenerates + commits the trees when templates change
  (the propagation safety net).
- **Projects list** — when wiring a NEW project to the marketplace, also append its repo root to
  `~/.config/mobile-pipeline/projects.txt` (Git-Bash style path, one per line) so `/mp --reflect`
  sees it; a weekly scheduled `/mp --reflect` is recommended (see `selfimprove/README.md` →
  "Scheduling the loop").
- **gh** — the auto-PR step needs the GitHub CLI (`gh`), authenticated (it reads `GITHUB_TOKEN`). Without
  it the scripts still push the `improve/*` branch and print the URL to open the PR manually.

See "Proposed alternatives" in `.ai/tasks/claude-003-marketplace.md` for the fully-automatic variant.

## Follow-ups

- ~~Fold intake/knowledge/planner into canonical `mp-dev`~~ — **done in v1.4.0** (planner is now the
  generic `/mp-spec`→backlog bridge; not MyMoney's PROGRESS.md spine).
- **MyMoney_app dev migration** — left on its bespoke `/cmp` (the `--phase`/`--check`/`--plan` PROGRESS.md
  workflow + `cmp.md` depends on the local `cmp-*` agents). Migrating it to `/mp` needs rewiring `cmp.md`'s
  agent references `cmp-*`→`mp-*` (the plugin agents + `.claude/mp/extras/` already replicate the
  MyMoney specifics) and deciding whether to keep `--phase`/`--check` as a project-local command or port
  to the backlog board. Do it as a focused, verified step — not a blind archive (would break the active pipeline).
- Optional installer automation for Codex **dev** agent shims. The skill/reference/template contract now
  exists; `lib/sync.sh` keeps the derived project adapter current, while the 21 project-local
  `.codex/agents/mp-*.toml` shims follow `templates/dev/codex/agent.toml.tmpl`.
- `lib/build-marketplace.sh` may later merge with the codex-owned `lib/sync.sh` (codex-001).

## Renaming the repo / folder (manual)

The marketplace `name` is already `mobile-pipeline`; the local folder is still
`claude-mobile-pipeline`. To rename the folder/remote (optional), do it yourself (it's the cwd):
`git remote set-url …`, move the directory, then update the `directory` source paths in the three
projects' `.claude/settings.json` (or switch to a git source).
