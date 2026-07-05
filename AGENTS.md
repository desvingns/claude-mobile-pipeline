# AGENTS.md — working on `claude-mobile-pipeline`

Canonical instructions for any AI tool working **on this repository**. Read by Codex CLI
natively; imported by `CLAUDE.md` for Claude Code via `@AGENTS.md`. This is the single source
of truth — do not duplicate these rules elsewhere.

## What this repo is

`claude-mobile-pipeline` (cmp) is a **generator**, not an app. `bootstrap.sh` renders the
`templates/` tree + a user-chosen `PREFIX` into a ready-to-use agent pipeline for a mobile
project (Android / iOS): specialist agents, an orchestrator command, deterministic bash
scripts, and cross-session memory. The thing we edit here is the *template system*, not a
running application.

## Golden rules (invariants — do not break)

1. **Cross-platform Bash only.** Every shell script must run on Linux, macOS, and Windows Git
   Bash. Never use PowerShell in pipeline scripts. Shebang `#!/usr/bin/env bash`.
2. **Never `sed -i`.** GNU and BSD `sed` differ. Always write to a temp file and `mv` (see
   `lib/render.sh`). This is the most common portability bug — respect it.
3. **Markdown-first.** Agents, memory, handoff, and the change-log are all plain markdown so
   any tool can read/write them without a custom parser. Keep it that way.
4. **Placeholders.** `{{KEY}}` tokens in file *content* and `{{PREFIX}}` in file *names* are
   substituted by `bootstrap.sh`. Content is rendered before filenames are renamed. New
   placeholders must be added to the vars file in `bootstrap.sh`.
5. **Conditional blocks.** `<!-- platform:X -->…<!-- /platform:X -->` and
   `<!-- if COND -->…<!-- /if -->` are trimmed by `lib/render.sh`. Author **at most one inline
   block per line** (the inline `sed` pass is greedy). The new `tool:` axis (below) follows the
   same rules.
6. **Memory is append-only.** Generated memory files are never overwritten by bootstrap; the
   `.ai/memory/` here is durable knowledge, extended not rewritten.
7. **Structured payloads.** Pipeline agents return exactly one structured payload (JSON or a
   BRAINSTORM block) — no prose around it. Deterministic scripts emit exactly one JSON line.
8. **SemVer.** PATCH = wording/typos; MINOR = new agents / optional sections (additive);
   MAJOR = renames or JSON-shape changes. Bump `VERSION` + `CHANGELOG.md` for any release.

## Repository map

```
bootstrap.sh              # entry point (PER-PROJECT dev pipeline): parse args → copy → render → strip → rename → memory → stamp
install-spec.sh           # GLOBAL installer for the spec tool → ~/.claude and/or ~/.codex (dual-harness; separate from bootstrap.sh)
lib/detect.sh             # OS / git / JBR / Xcode detection, path sanitising
lib/prompts.sh            # interactive prompt helpers
lib/render.sh             # placeholder replacement + conditional-block trimming (the render engine)
lib/sync.sh               # (to be built) consume .ai/changes/ → regenerate per-tool adapters
templates/common/         # tool- & platform-neutral: architect, docs, reviewer-base, maintainer, the orchestrator command, memory, root docs
templates/android/        # Android specialists, scripts (runner/reviewer .sh), memory, snippets
templates/ios/            # iOS specialists (stubs — being fleshed out)
templates/spec/           # GLOBAL spec-creation tool: app-spec-creator skill + 17 neutral spec agents + prompt library + codex/ adapters (installed by install-spec.sh — see docs/SPEC-PIPELINE.md)
templates/dev/codex/      # Codex mp-dev skill bridge + per-project native .codex/agents/mp-*.toml shim templates
docs/                     # USAGE, ARCHITECTURE, UPGRADE, ADDING-PLATFORM, local-llm (design notes)
.ai/                      # shared cross-tool workspace (memory / handoff / tasks / changes) — see .ai/README.md
AGENTS.md / CLAUDE.md     # this file (canonical) + thin Claude import
```

## Dual-tool model (the core design)

cmp is driven by **both Claude Code and Codex CLI**, at two levels — (A) we co-develop this
repo with both tools; (B) `bootstrap.sh` emits config for both into generated projects.

Pattern: **one canonical source + thin per-tool adapters.**

- **`AGENTS.md` is canonical**; `CLAUDE.md` is a thin `@AGENTS.md` import + Claude-only notes.
- Agent / orchestrator prose stays **tool-neutral**. The few genuinely tool-specific lines are
  isolated behind `<!-- tool:claude -->…<!-- /tool:claude -->` and
  `<!-- tool:codex -->…<!-- /tool:codex -->` markers — the same engine that handles
  `platform:`. Claude bootstraps keep the `claude` branch; Codex keeps the `codex` branch.
- **`{{AGENT_DIR}}`** resolves to `.claude` or `.codex` so paths like
  `{{AGENT_DIR}}/scripts/...` work for either tool.
- The Codex adapters (`AGENTS.md`, `.codex/`) in a generated project are **derived** from the
  canonical agent specs by `lib/sync.sh` — never hand-maintained twice.

Why this way (industry best practice): see `.ai/memory/dual-tool-architecture.md`.

## The `.ai/` workspace + coordination protocol

All cross-tool coordination lives in `.ai/` (git-tracked). Read `.ai/README.md` for the full
protocol. In short, **every session**:

1. **Start** — read this file → `.ai/handoff.md` → `.ai/memory/MEMORY.md` → open `.ai/tasks/*`.
2. **During** — keep your task file's `STATUS` current; log each agent/skill/template edit in
   `.ai/changes/agent-skill-log.md` (format: `.ai/changes/README.md`).
3. **Hand-off / end** — rewrite `.ai/handoff.md` (DONE / DECISIONS / NEXT / OWNER / BLOCKERS)
   and commit it with your work. Transport between tools is git: commit, and the other tool
   sees it on its next run. Do not touch files another tool lists under IN PROGRESS.

## Change-log + incremental sync

When you improve an agent or skill, record it **once** as an append-only entry in
`.ai/changes/agent-skill-log.md`. A sync then reads only entries newer than the per-adapter
cursor in `.ai/changes/sync-state.json` — never the whole system. `lib/sync.sh` is the
consumer/propagator and the only writer of the cursor. See `.ai/memory/change-log-discipline.md`.

## How to work & verify

- Understand a change end-to-end before editing — trace it through `bootstrap.sh` (copy →
  render → strip → rename phases) and `lib/render.sh`.
- **Dry run:** `./bootstrap.sh --dry-run --platform=android --prefix=ft --project-name=Demo
  --package=com.demo.app` shows planned outputs without writing.
- **Lint:** `bash -n <script>` and `shellcheck` must be clean for any touched `.sh`.
- **Smoke test:** bootstrap into a throwaway dir, then grep the output to confirm no
  `<!-- platform:* -->` / `<!-- tool:* -->` / `{{...}}` markers leaked into rendered files.
- Don't break back-compat: a `claude`-only bootstrap must produce the same `.claude/` output as
  before the dual-tool work.

## Ownership while building the dual-tool support

To avoid collisions, work is split by file ownership; the seams are pinned in
`.ai/tasks/codex-001-dual-tool.md` (the authoritative contract for the shared interfaces).

- **Codex owns:** `lib/render.sh` (the `tool:` axis), `lib/sync.sh` (new), `bootstrap.sh`
  (`--tools`, `{{AGENT_DIR}}`, adapter-emission phase), the `.codex/` config + prompt templates,
  and verifying the bash scripts are path-neutral.
- **Claude owns:** the canonical `AGENTS.md` prose, the `tool:` branches inside agent /
  orchestrator templates, the `.ai/` scaffold + protocol + schemas, and the docs / version bump.

**Shared seams (agreed, do not change unilaterally):** the `{{AGENT_DIR}}` name; the
`<!-- tool:claude|codex -->` marker syntax + semantics; the change-log entry format and
`sync-state.json` shape; and the `lib/sync.sh` input/output contract. All four are specified in
`.ai/tasks/codex-001-dual-tool.md`.

## Second brain (cross-project knowledge)

Cross-project knowledge lives in `D:/Pet/brain` (private repo `github.com/desvingns/brain`);
entry point `INDEX.md`, this repo's card: `brain/projects/mobile-pipeline.md`. Lessons that
generalize beyond cmp go to `brain/inbox/` (see the `/brain` skill); promotion is human-gated.
Project-local knowledge stays in `.ai/memory/` as before.

## graphify

This project has a knowledge graph at graphify-out/ with god nodes, community structure, and cross-file relationships.

When the user types `/graphify`, invoke the `skill` tool with `skill: "graphify"` before doing anything else.

Rules:
- For codebase questions, first run `graphify query "<question>"` when graphify-out/graph.json exists. Use `graphify path "<A>" "<B>"` for relationships and `graphify explain "<concept>"` for focused concepts. These return a scoped subgraph, usually much smaller than GRAPH_REPORT.md or raw grep output.
- Dirty graphify-out/ files are expected after hooks or incremental updates; dirty graph files are not a reason to skip graphify. Only skip graphify if the task is about stale or incorrect graph output, or the user explicitly says not to use it.
- If graphify-out/wiki/index.md exists, use it for broad navigation instead of raw source browsing.
- Read graphify-out/GRAPH_REPORT.md only for broad architecture review or when query/path/explain do not surface enough context.
- After modifying code, run `graphify update .` to keep the graph current (AST-only, no API cost).
