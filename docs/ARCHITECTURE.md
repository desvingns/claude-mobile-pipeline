# ARCHITECTURE — how cmp works

This document explains the agent graph, how context flows between agents, and why each
layer exists. For a high-level overview, see `README.md`. For per-flag behaviour, see
`docs/USAGE.md`.

## Repository shape (v1.3+)

cmp now has two independent halves:

- **Per-project dev pipeline** — `bootstrap.sh` + `templates/{common,android,ios}/`. Installs a
  `/<prefix>` orchestrator + specialist agents into a project's `.claude/` / `.codex/`. This is
  what the rest of this document covers.
- **Global spec tool** — `install-spec.sh` + `templates/spec/`. Installs `app-spec-creator`
  once per machine into `~/.claude/` and/or `~/.codex/`. Takes an app idea or screenshots and
  produces a traceable `spec/` bundle for handoff to the dev pipeline. See `docs/SPEC-PIPELINE.md`.

Both halves share the same golden rules (cross-platform Bash, markdown-first, `{{AGENT_DIR}}`
placeholder, `<!-- tool:* -->` conditional blocks) and the same dual-harness model.

## Agent graph

```
                          USER
                            │
                            ▼
                ┌───────────────────────┐
                │  /<prefix> command    │
                │  (orchestrator)       │
                └───────────┬───────────┘
                            │
   ┌──────┬──────┬──────┬───┴──┬──────┬──────┬──────┬──────────┐
   ▼      ▼      ▼      ▼      ▼      ▼      ▼      ▼          ▼
architect docs reviewer tester runner developer verifier  coverage
   │      │      │      │      │      │      │      │
  Read/  Bash/  Bash/  Read/  Bash   Bash/  Read/  Bash/
  Glob/  Read/  Read/  Write/        Read/  Glob/  Read/
  Grep   Edit   Glob/  Edit/         Write/ Grep/  Glob/
                Grep   Glob/         Edit/  Bash   Grep
                       Grep          Glob/
                                     Grep
```

`coverage` is opt-in (only invoked from `--coverage`); the others run as part of
`--feature` / `--bugfix` chains.

Each agent is a Markdown file in `.claude/agents/` with a `frontmatter`:
```yaml
---
name: <prefix>-<role>-<platform>
description: <one sentence — Claude Code uses this to decide when to invoke>
tools: <comma-separated list — limits what the agent can do>
---
```

The orchestrator spawns the right agent for each step, passing a structured prompt.

## Context flow — default `--feature` workflow

```
USER input
   ↓
Phase 0: Brainstorm trigger?
   ↓ (if yes → spawn architect, USER picks option)
Phase 1: Spec (≤3 questions, USER approves)
   ↓ SPEC block
Step 1: developer       → CHANGED_FILES + commit hash
   ↓
Step 1.5: reviewer      → {pass, violations[]}   ← BLOCKS if pass=false
   ↓
Step 2: tester          → {test_files[], screenshot_record_needed}
   ↓
Step 3: runner          → {pass, tests, detekt, screenshots}
   ↓
Step 4 (optional retry): developer + runner ×1
   ↓
Step 4.5: verifier      → {pass, static_checks{}, manual_checklist[]}  ← BLOCKS if pass=false
   ↓ USER reads checklist, confirms y/N        ← GATE
Step 5: git push
   ↓
Step 6: docs            → updates STATE.md (always) + DOC/CLAUDE (if new)
```

Each arrow is **just enough context** for the next agent — never the whole conversation.
That's why orchestrator parses each agent's JSON response and re-prompts the next with
extracted fields.

## Context flow — `--tdd` mode (RED-GREEN)

```
Phase 0/1 identical to default.

Step 1: tester (red_phase=true)    → {test_files[], phase:"red", expected_failures[]}
                                      Writes only unit tests. Production code doesn't exist.
   ↓
Step 2: runner (interpret red)    → orchestrator decides:
                                      failing tests + detekt ok = expected red → continue
                                      0 failed = tester failed → STOP
                                      compile errors in test code = STOP
   ↓
Step 3: developer (green_phase=true, TEST_FILES=[...])
                                    → implements until tests pass
   ↓
Step 3.5: reviewer
   ↓
Step 4: tester (default mode, second pass)
                                    → fills in dao / compose-ui / screenshot tests
   ↓
Step 5+: same as default Step 3+
```

## Why each agent exists

| Agent | Purpose | Why separate (not part of orchestrator) |
|---|---|---|
| `architect` | Surfacing 2-3 options before SPEC | Read-only, no write tools → forces it to investigate, not invent |
| `developer` | Writes production code | Has Write/Edit/Bash → can break things → isolated scope per SPEC |
| `reviewer` | Clean Arch + design-system + test-hygiene checks | Read-only → can't fix anything → forces it to **stop the chain**, not patch |
| `tester` | Writes tests, never runs them. Enforces Mandatory Coverage Rules (one file per class, no use-case grouping) | Separation prevents test-after fragility |
| `runner` | Runs gradle / xcodebuild, parses results, enforces lint + coverage threshold | Bash-only → mechanically reports, doesn't interpret |
| `verifier` | Static checks (nav, DI, schema, UI strings, tests-exist) + manual checklist | Catches the gap between "tests pass" and "feature visible to user" |
| `docs` | Refreshes STATE/DOC/CLAUDE | Three different files with different cadence — single agent enforces consistency |
| `coverage` (Android only, opt-in) | Reports JaCoCo coverage per package, suggests "test next" candidates | Diagnostic — not part of `--feature` chain; user invokes via `--coverage` |

**Single Responsibility Principle for agents.** If one agent did everything, it would
need too many tools (Write + Bash + everything), too long a prompt, and would
context-switch poorly between modes. Splitting reduces prompt length, narrows tool
scope per role, and makes failures localised.

## State files

Three Markdown files at project root, each with a distinct purpose. Never duplicate
content across them — there's a clear rule for "which file does this fact belong in":

| File | Cadence | What lives here |
|---|---|---|
| `STATE.md` | **Always refreshed** after each `/<prefix>` run | Current iteration, in-flight work, last 5 commits, up-next |
| `ROADMAP.md` | Manual edits, occasional `--roadmap` flag | Planned iterations, ordered, with checkboxes |
| `DOCUMENTATION.md` | When something genuinely new ships | Feature changelog, screens, user flows, architecture decisions |
| `CLAUDE.md` | When developer-facing facts change | Stack, routes, build commands, key technical decisions |

The `docs` agent enforces this split.

## Memory

`~/.claude/projects/<sanitised-cwd>/memory/` is **cross-session, cross-conversation** knowledge.

```
MEMORY.md              ← flat index, auto-loaded into every Claude Code session
├── user-coding-style.md             ← user prefs (RU UI, learning project, ...)
├── testing-fakes-only.md             ← repo policy (no mocks)
├── architecture-clean-rationale.md   ← why 7 layers, not 3
├── dao-test-config-trap.md           ← Robolectric/Room trap (Android)
├── room-upsert-by-pk-not-unique.md   ← Room behaviour (Android)
├── screen-content-extraction.md      ← Compose testing pattern (Android)
├── cross-platform-bash.md            ← Bash everywhere, never PowerShell (common)
├── cross-platform-bash-jbr.md        ← JBR detection (Android)
├── git-push-via-token.md             ← origin credential helper + optional token fallback (common)
└── iteration-progression.md          ← project history & iteration cadence
```

This survives across sessions, across `--continue`, across `--resume`. It's where you
record `**why**`-facts, not `**what**`-facts: rules, traps, preferences. `**What**`-facts
(file paths, function names) are derivable from reading the repo — don't waste memory
on them.

### Cross-project user profile

One memory layer sits ABOVE projects: `$MP_USER_PROFILE` or
`~/.config/mobile-pipeline/user-profile.md` (same root as `projects.txt`) — durable facts about
the **user**, not about any app: UI/design taste, language, naming style, process tolerance.
Sections: `UI & design taste` / `Process preferences` / `Tech defaults` / `Anti-patterns`; one
fact per bullet with provenance `(project, date, source)`; append-mostly with merge rules (the
skeleton + rules live in the `knowledge` agent).

- **Writers:** the `knowledge` agent (`user_preference` lessons, post-ship) and the `--fit`
  taste journal (gated y/N — preference candidates inferred from *intended* deviations).
- **Readers:** the `/<prefix> --feature` grill (Startup) and the `/mp-spec` grill + greenfield
  stages — profile facts bias **recommended answers and defaults only**; they never auto-decide,
  and a missing profile changes nothing.

This is how the pipeline gets better at understanding the user across pet projects instead of
re-learning them from zero each time.

## Why 3 docs files instead of 1

Three different cadences. A single file would force every update to touch the whole
file. Three files keeps each commit small and focused:

- **STATE.md** changes every `/<prefix>` run. ~20 lines diff each time.
- **DOCUMENTATION.md** changes when a real feature ships. ~5 lines per iteration.
- **CLAUDE.md** changes rarely — only when developer-facing stack info shifts.

If you merge them, every run produces a "tinkering with STATE section" diff that mixes
with rare CLAUDE-section updates, making git history noisy.

## Test coverage as a first-class concern (added in 1.1)

Three layered defences ensure every new prod class ships with a dedicated test:

1. **Tester — Mandatory Coverage Rules.** A table inside the `tester` agent maps prod-file
   patterns to required test-file paths. If a new `*UseCase.kt` lands in CHANGED_FILES, the
   tester emits a matching `*UseCaseTest.kt` even when SPEC.TEST_TYPES didn't list it. New
   use cases get their own file — no appending to legacy `*UseCasesTest.kt` group files.

2. **Reviewer — Test Hygiene (Check 6).** After the tester writes, the reviewer scans the
   new test files for `@Ignore` without issue ref, empty `@Test`, trivially-true assertions,
   `Thread.sleep`, and `runBlocking`. Violations block the chain.

3. **Verifier — `tests_exist` (Check 5).** Before push, the verifier cross-checks each new
   prod file against the expected test path. A missing test (without an explicit
   `coverage_exceptions` entry from the tester) blocks the push.

Plus a quantitative gate inside the runner: **JaCoCo coverage threshold** (default 65%
line coverage, configurable). Below the threshold → fail-close.

The combined effect: a feature can't ship with a silent test-coverage regression. The
existing reviewer/runner/verifier chain already enforces architectural correctness; the
1.1 additions extend the same chain to enforce test discipline.

## Workflow alternatives

cmp ships with one workflow shape: linear pipeline with optional brainstorm prefix and
optional TDD reordering. If you want different shapes (parallel agents via worktrees,
event-driven pipelines, ...), see `CUSTOMIZATION.md` Option 2 (fork).

The current shape was chosen because:
- Sequential is easier to debug than parallel
- Linear pipelines map naturally to git's linear commit history
- Each step has one clear input/output contract
- TDD mode only swaps Step 1 ↔ Step 2 — minimal restructure
