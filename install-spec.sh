#!/usr/bin/env bash
# install-spec.sh — global install of the app-spec-creator spec pipeline for Claude Code and/or
# Codex CLI. Part of claude-mobile-pipeline. The spec tool is project-agnostic (fixed names), so it
# installs once into ~/.claude and/or ~/.codex — unlike the per-project dev pipeline (bootstrap.sh).
#
# NOTE (v1.4.0+): the spec tool is now also distributed as the `mp-spec` plugin in the
# `mobile-pipeline` marketplace (see README → Marketplace + docs/MARKETPLACE.md). Prefer enabling the
# plugin per project (one shared, updatable copy). This global installer is still useful for Codex
# sub-agents (`~/.codex/agents/*.toml` — which Codex plugins can't carry) and as a fallback; if you
# enable the plugin AND keep this global install, remove the older global copy to avoid duplicate
# skill/agent names (~/.claude/skills/app-spec-creator + ~/.claude/agents/<22 spec agents>).
#
# Golden rules honoured: cross-platform Bash (Linux/macOS/Windows Git Bash); never `sed -i`
# (render writes to a temp file then `mv`); markdown-first; structured payloads untouched.
#
#   ./install-spec.sh [--harness claude|codex|both] [--home DIR] [--dry-run] [--force]
#
# Defaults: --harness both, --home "$HOME".
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPEC_SRC="$SCRIPT_DIR/templates/spec"

HARNESS="both"
HOME_DIR="${HOME}"
DRY_RUN=0
FORCE=0
INSTALL_STAMP="$(date -u +%Y%m%dT%H%M%SZ)-$$"

while [ $# -gt 0 ]; do
  case "$1" in
    --harness=*) HARNESS="${1#*=}" ;;
    --harness)   HARNESS="${2:?--harness needs a value}"; shift ;;
    --home=*)    HOME_DIR="${1#*=}" ;;
    --home)      HOME_DIR="${2:?--home needs a value}"; shift ;;
    --dry-run)   DRY_RUN=1 ;;
    --force)     FORCE=1 ;;
    -h|--help)   echo "usage: install-spec.sh [--harness claude|codex|both] [--home DIR] [--dry-run] [--force]"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
  shift
done

[ -d "$SPEC_SRC" ] || { echo "spec source not found: $SPEC_SRC" >&2; exit 1; }

# Canonical Codex agent table: name|model|reasoning_effort|short_description
# (no '#' or '/' in description).
AGENTS='constitution-author|gpt-5.4-mini|medium|Generate the spec bundle constitution.md (standards layer) from project conventions.
grounding-scout|gpt-5.4-mini|medium|Read-only brownfield grounding scout; fan out over the target repo and return verified file:line facts plus the project SPEC-board format. No writes.
requirements-author|gpt-5.4|high|Author EARS functional requirements from analyzer outputs or interview answers; ground every FR.
user-story-writer|gpt-5.4|high|Derive user stories (US-NNN) from requirements, linked to FR IDs, reporting coverage gaps.
acceptance-criteria-writer|gpt-5.4|high|Write UI-agnostic Gherkin acceptance criteria per epic, covering the state matrix.
spec-evaluator|gpt-5.6|xhigh|Evaluator-optimizer critic; cross-check the bundle, build traceability.csv, return a verdict. Read-only on artifacts.
nfr-analyzer|gpt-5.4|medium|Derive measurable non-functional requirements with numeric thresholds.
a11y-reviewer|gpt-5.4|medium|Produce the accessibility spec (WCAG 2.2 AA) plus a per-screen checklist.
security-privacy-reviewer|gpt-5.4|medium|Data classification, consent, and per-permission justification.
analytics-taxonomy-designer|gpt-5.4|medium|Design the analytics event taxonomy keyed to user stories.
risk-estimator|gpt-5.4|medium|Risk register plus effort estimate from inventory, NFRs, and integrations.
apk-analyzer|gpt-5.4|medium|Extract ground-truth from an APK (palette, strings, manifest, libraries).
play-store-scraper|gpt-5.4-mini|low|Scrape a Google Play listing for app metadata (needs the Chrome MCP).
screenshot-business-analyzer|gpt-5.6|high|Multimodal screenshot analysis into screens, business rules, states, and hints.
screenshot-style-analyzer|gpt-5.6|high|Multimodal screenshot analysis into design tokens and contrast pairs.
navigation-flow-analyzer|gpt-5.4|medium|Build the navigation graph from the business analysis.
data-model-extractor|gpt-5.4|high|Derive neutral data entities, relations, and a cache strategy.
backend-api-extractor|gpt-5.4|high|Infer REST API contracts and third-party SDKs from UI evidence.
fit-checklist-author|gpt-5.6|high|Per-screen visual+behavioural fit checklist + screen<->reference registry + intended-deviation ledger (clone, depth reference).
crawl-executor|gpt-5.6|high|Driver of the reference-APK crawl trio; goal-scoped vision-first device driver — replay to a target state, perform one affordance, capture and dedup (clone, --graph).
crawl-navigator|gpt-5.4|medium|Planner of the reference-APK crawl trio; read the observed state graph and pick the next affordance to explore plus its replay path (clone, --graph).
crawl-reviewer|gpt-5.6|high|Critic of the reference-APK crawl trio; multimodal — classify each explored edge, score coverage confidence, gate accept vs retry (clone, --graph).'

say() { echo "$@"; }

path_exists() { [ -e "$1" ] || [ -L "$1" ]; }

# prepare_install <harness-root> <skill-dir> <agents-dir> <claude|codex>
#
# A global install may contain user edits or locally maintained agents. Never
# replace those paths in place: without --force, refuse; with --force, move the
# complete prior skill plus every agent path owned by this installer into one
# timestamped archive under the harness root.
prepare_install() {
  local harness_root="$1" sk="$2" ag="$3" tool="$4"
  local archive="$harness_root/archive/app-spec-creator/$INSTALL_STAMP"
  local extensions name ext path conflict=0 archived=0
  if [ "$tool" = claude ]; then extensions="md"; else extensions="md toml"; fi

  path_exists "$sk" && conflict=1
  while IFS='|' read -r name _ _ _; do
    [ -n "$name" ] || continue
    for ext in $extensions; do
      path="$ag/$name.$ext"
      path_exists "$path" && conflict=1
    done
  done <<EOF
$AGENTS
EOF

  [ "$conflict" -eq 1 ] || return 0
  if [ "$DRY_RUN" = 1 ]; then
    say "  [dry] archive prior $tool install -> $archive"
    return 0
  fi
  [ "$FORCE" = 1 ] || {
    echo "refusing to overwrite an existing $tool spec skill/agent path (use --force to archive it first)" >&2
    exit 1
  }

  if path_exists "$sk"; then
    mkdir -p "$archive/skills"
    mv "$sk" "$archive/skills/app-spec-creator"
    archived=1
  fi
  while IFS='|' read -r name _ _ _; do
    [ -n "$name" ] || continue
    for ext in $extensions; do
      path="$ag/$name.$ext"
      path_exists "$path" || continue
      mkdir -p "$archive/agents"
      mv "$path" "$archive/agents/$(basename "$path")"
      archived=1
    done
  done <<EOF
$AGENTS
EOF
  [ "$archived" -eq 0 ] || say "    archived prior $tool install -> $archive"
}

# render a markdown file: substitute {{AGENT_DIR}}; drop the OTHER tool's conditional blocks; strip
# all remaining tool-marker lines. $agentdir is a portable literal ("~/.claude" / "~/.codex").
render_md() {
  local src="$1" dst="$2" agentdir="$3" tool="$4" other tmp
  if [ "$tool" = claude ]; then other=codex; else other=claude; fi
  if [ "$DRY_RUN" = 1 ]; then echo "  [dry] render $(basename "$src") -> $dst ($tool)"; return; fi
  tmp="$(mktemp)"
  sed "s#{{AGENT_DIR}}#${agentdir}#g" "$src" \
    | sed "/<!-- tool:${other} -->/,/<!-- \/tool:${other} -->/d" \
    | sed -e "/<!-- tool:claude -->/d" -e "/<!-- \/tool:claude -->/d" \
          -e "/<!-- tool:codex -->/d"  -e "/<!-- \/tool:codex -->/d" \
    > "$tmp"
  mv "$tmp" "$dst"
}

install_claude() {
  local home="$1" sk ag adir="~/.claude" name
  sk="$home/.claude/skills/app-spec-creator"; ag="$home/.claude/agents"
  say "==> Claude form -> $home/.claude"
  prepare_install "$home/.claude" "$sk" "$ag" claude
  if [ "$DRY_RUN" != 1 ]; then
    mkdir -p "$sk" "$ag"
    cp -r "$SPEC_SRC/skills/app-spec-creator/prompts" "$sk/prompts"
    [ ! -d "$SPEC_SRC/skills/app-spec-creator/scripts" ] || cp -r "$SPEC_SRC/skills/app-spec-creator/scripts" "$sk/scripts"
  fi
  render_md "$SPEC_SRC/skills/app-spec-creator/SKILL.md" "$sk/SKILL.md" "$adir" claude
  while IFS='|' read -r name _ _ _; do
    [ -n "$name" ] || continue
    render_md "$SPEC_SRC/agents/$name.md" "$ag/$name.md" "$adir" claude
  done <<EOF
$AGENTS
EOF
}

install_codex() {
  local home="$1" sk ag adir="~/.codex" tmpl cfg name model effort desc out
  sk="$home/.codex/skills/app-spec-creator"; ag="$home/.codex/agents"
  tmpl="$SPEC_SRC/codex/agent.toml.tmpl"
  say "==> Codex form -> $home/.codex"
  prepare_install "$home/.codex" "$sk" "$ag" codex
  if [ "$DRY_RUN" != 1 ]; then
    mkdir -p "$sk/agents" "$ag"
    cp -r "$SPEC_SRC/skills/app-spec-creator/prompts" "$sk/prompts"
    [ ! -d "$SPEC_SRC/skills/app-spec-creator/scripts" ] || cp -r "$SPEC_SRC/skills/app-spec-creator/scripts" "$sk/scripts"
    cp "$SPEC_SRC/codex/skills/app-spec-creator/agents/openai.yaml" "$sk/agents/openai.yaml"
  fi
  render_md "$SPEC_SRC/skills/app-spec-creator/SKILL.md" "$sk/SKILL.md" "$adir" codex
  while IFS='|' read -r name model effort desc; do
    [ -n "$name" ] || continue
    render_md "$SPEC_SRC/agents/$name.md" "$ag/$name.md" "$adir" codex     # canonical spec the shim reads
    if [ "$DRY_RUN" = 1 ]; then echo "  [dry] toml $ag/$name.toml"; continue; fi
    out="$(mktemp)"
    sed -e "s#{{NAME}}#${name}#g" -e "s#{{MODEL}}#${model}#g" \
        -e "s#{{EFFORT}}#${effort}#g" \
        -e "s#{{AGENT_DIR}}#${adir}#g" -e "s#{{DESC}}#${desc}#g" "$tmpl" > "$out"
    mv "$out" "$ag/$name.toml"
  done <<EOF
$AGENTS
EOF
  cfg="$home/.codex/config.toml"
  if [ -f "$cfg" ] && grep -q '^\[agents\]' "$cfg" 2>/dev/null; then
    say "    NOTE: $cfg already defines [agents] — merge templates/spec/codex/config-fragment.toml by hand (need max_threads >= 6)."
  elif [ "$DRY_RUN" != 1 ]; then
    say "    appending [agents] to $cfg"
    cat "$SPEC_SRC/codex/config-fragment.toml" >> "$cfg"
  fi
}

case "$HARNESS" in
  claude) install_claude "$HOME_DIR" ;;
  codex)  install_codex  "$HOME_DIR" ;;
  both)   install_claude "$HOME_DIR"; install_codex "$HOME_DIR" ;;
  *) echo "bad --harness: $HARNESS (want claude|codex|both)" >&2; exit 2 ;;
esac

say "Done ($([ "$DRY_RUN" = 1 ] && echo dry-run || echo installed)). Verify: grep -R '{{' the installed dirs should find nothing."
