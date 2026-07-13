#!/usr/bin/env bash
# build-marketplace.sh — emit the committed plugin trees (claude-plugins/, codex-plugins/)
# from the canonical templates/ sources. Principle: ONE canonical source + thin per-tool adapters,
# so you edit templates/ once and regenerate the marketplace instead of hand-syncing copies.
#
# Golden rules honoured: cross-platform Bash (Linux/macOS/Windows Git Bash); never `sed -i`
# (render writes to a temp file then `mv`); markdown-first.
#
#   ./lib/build-marketplace.sh [--dry-run|--check-runtime]
#
# What it builds:
#   claude-plugins/mp-spec/  skills/mp-spec/{SKILL.md,prompts/} + agents/*.md   (skill + 22 subagents)
#   codex-plugins/mp-spec/   skills/mp-spec/{SKILL.md,prompts/}                  (skill only — Codex
#                            plugins cannot carry subagents; the .codex/agents/*.toml roster is
#                            installed per-project by install-spec.sh.)
#   claude-plugins/mp-dev/   commands/{mp.md,mp-runtime/} + agents/mp-*.md + scripts/mp-*.sh
#                            (the /mp dev pipeline,
#                            de-specialized: agent bodies read project facts from .claude/mp/config.json
#                            + CLAUDE.md + .claude/mp/extras/*.md at runtime).
#   codex-plugins/mp-dev/    skills/mp-dev/{SKILL.md,references/runtime/,scripts/}
#                            (skill + self-contained deterministic scripts; native
#                            .codex/agents/mp-*.toml shims stay per-project and use
#                            templates/dev/codex/agent.toml.tmpl).
#
# Ownership: this script never edits templates/ — it reads them and writes transformed copies into
# the plugin trees. bootstrap.sh and templates/**/scripts/*.sh stay untouched.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SPEC_SRC="$ROOT/templates/spec"
DEV_CODEX="$ROOT/templates/dev/codex"
COMMON="$ROOT/templates/common"
ANDROID="$ROOT/templates/android"
CMP_VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"

# strip_platform_block / strip_platform_markers / strip_if_markers come from lib/render.sh
# (sourcing only DEFINES functions — no side effects).
# shellcheck source=lib/render.sh
. "$ROOT/lib/render.sh"

DRY=0
CHECK_RUNTIME=0
case "${1:-}" in
  "") ;;
  --dry-run)      DRY=1 ;;
  --check-runtime) CHECK_RUNTIME=1 ;;
  *) echo "usage: $0 [--dry-run|--check-runtime]" >&2; exit 2 ;;
esac

[ -d "$SPEC_SRC" ] || { echo "spec source not found: $SPEC_SRC" >&2; exit 1; }
[ -d "$DEV_CODEX" ] || { echo "dev codex source not found: $DEV_CODEX" >&2; exit 1; }

WORK=""
ARCHIVE_DIR=""

archive_existing() {
  local path="$1" bucket="${2:-replaced}" rel dest
  [ -e "$path" ] || return 0
  [ -n "$ARCHIVE_DIR" ] || { echo "archive directory is not initialized" >&2; return 1; }
  rel="${path#"$ROOT"/}"
  dest="$ARCHIVE_DIR/$bucket/$rel"
  if [ -e "$dest" ]; then dest="$dest.$(date -u +%H%M%S)-$$"; fi
  mkdir -p "$(dirname "$dest")"
  mv "$path" "$dest"
}

archive_copy() {
  local path="$1" rel dest
  [ -f "$path" ] || return 0
  rel="${path#"$ROOT"/}"
  dest="$ARCHIVE_DIR/metadata/$rel"
  [ -f "$dest" ] && return 0
  mkdir -p "$(dirname "$dest")"
  cp "$path" "$dest"
}

# ----- shared md render (mp-spec): {{AGENT_DIR}} + tool: only; leave platform: inert ------------
render_md() {
  local src="$1" dst="$2" agentdir="$3" tool="$4" other tmp
  if [ "$tool" = claude ]; then other=codex; else other=claude; fi
  if [ "$DRY" = 1 ]; then echo "  [dry] render $(basename "$src") -> ${dst#"$ROOT"/} ($tool)"; return; fi
  mkdir -p "$(dirname "$dst")"
  tmp="$(mktemp)"
  sed "s#{{AGENT_DIR}}#${agentdir}#g" "$src" \
    | sed "/<!-- tool:${other} -->/,/<!-- \/tool:${other} -->/d" \
    | sed -e "/<!-- tool:claude -->/d" -e "/<!-- \/tool:claude -->/d" \
          -e "/<!-- tool:codex -->/d"  -e "/<!-- \/tool:codex -->/d" \
    > "$tmp"
  mv "$tmp" "$dst"
}

set_skill_name() {
  local file="$1" newname="$2" tmp
  [ "$DRY" = 1 ] && return 0
  tmp="$(mktemp)"
  awk -v n="$newname" 'BEGIN{done=0} (!done && /^name:[[:space:]]/){print "name: " n; done=1; next} {print}' "$file" > "$tmp"
  mv "$tmp" "$file"
}

copy_dir() {
  local src="$1" dst="$2"
  [ -d "$src" ] || return 0
  if [ "$DRY" = 1 ]; then echo "  [dry] copy   ${src#"$ROOT"/} -> ${dst#"$ROOT"/}"; return; fi
  archive_existing "$dst" replaced
  mkdir -p "$(dirname "$dst")"
  cp -r "$src" "$dst"
}

set_json_version() {
  local file="$1" version="$2" tmp
  [ -f "$file" ] || return 0
  if [ "$DRY" = 1 ]; then echo "  [dry] version ${file#"$ROOT"/} -> $version"; return; fi
  tmp="$(mktemp)"
  awk -v v="$version" '
    BEGIN { done = 0 }
    !done && /^[[:space:]]*"version"[[:space:]]*:/ {
      sub(/"version"[[:space:]]*:[[:space:]]*"[^"]*"/, "\"version\": \"" v "\"")
      done = 1
    }
    { print }
  ' "$file" > "$tmp"
  mv "$tmp" "$file"
}

sync_manifest_versions() {
  local f
  for f in \
    "$ROOT/.claude-plugin/marketplace.json" \
    "$ROOT/claude-plugins/mp-dev/.claude-plugin/plugin.json" \
    "$ROOT/claude-plugins/mp-spec/.claude-plugin/plugin.json" \
    "$ROOT/codex-plugins/mp-dev/.codex-plugin/plugin.json" \
    "$ROOT/codex-plugins/mp-spec/.codex-plugin/plugin.json" \
    "$DEV_CODEX/.codex-plugin/plugin.json"
  do
    [ "$DRY" = 1 ] || archive_copy "$f"
    set_json_version "$f" "$CMP_VERSION"
  done
}

rewrite_mp_spec_file() {
  local file="$1" tool="$2" prompt_root tmp
  if [ "$tool" = claude ]; then
    prompt_root='${CLAUDE_PLUGIN_ROOT}/skills/mp-spec/prompts'
  else
    prompt_root='prompts'
  fi

  tmp="$(mktemp)"
  sed -e "s#{{AGENT_DIR}}/skills/app-spec-creator/prompts#${prompt_root}#g" \
      -e "s#\\.claude/skills/app-spec-creator/prompts#${prompt_root}#g" \
      -e "s#\\.codex/skills/app-spec-creator/prompts#${prompt_root}#g" \
      -e 's#/app-spec-creator#/mp-spec#g' \
      -e 's#app-spec-creator#mp-spec#g' \
      "$file" > "$tmp"
  mv "$tmp" "$file"

  tmp="$(mktemp)"
  if [ "$tool" = claude ]; then
    sed -e 's#^- Skill + agents live under `~/.claude/`; prompts at `.*`\.$#- Skill + agents live inside the `mp-spec` plugin; prompts at `${CLAUDE_PLUGIN_ROOT}/skills/mp-spec/prompts/`.#' \
        "$file" > "$tmp"
  else
    sed -e 's#^- Skill + agents live under `~/.codex/`; prompts at `.*`\.$#- Skill lives inside the `mp-spec` plugin; Codex sub-agent shims are installed separately; prompts live next to this SKILL.md under `prompts/`.#' \
        "$file" > "$tmp"
  fi
  mv "$tmp" "$file"
}

rewrite_mp_spec_tree() {
  local dir="$1" tool="$2" f
  [ "$DRY" = 1 ] && return 0
  while IFS= read -r f; do
    rewrite_mp_spec_file "$f" "$tool"
  done < <(find "$dir" -type f \( -name '*.md' -o -name '*.json' -o -name '*.yaml' -o -name '*.yml' \) -print)
}

# ----- mp-spec ----------------------------------------------------------------------------------
build_mp_spec() {
  local tool="$1" adir plugdir a
  if [ "$tool" = claude ]; then adir=".claude"; plugdir="$ROOT/claude-plugins/mp-spec"
  else                        adir=".codex";  plugdir="$ROOT/codex-plugins/mp-spec"; fi
  echo "==> mp-spec ($tool) -> ${plugdir#"$ROOT"/}"
  render_md "$SPEC_SRC/skills/app-spec-creator/SKILL.md" "$plugdir/skills/mp-spec/SKILL.md" "$adir" "$tool"
  set_skill_name "$plugdir/skills/mp-spec/SKILL.md" "mp-spec"
  copy_dir "$SPEC_SRC/skills/app-spec-creator/prompts" "$plugdir/skills/mp-spec/prompts"
  # Crawl device primitives (.sh) — copied verbatim; rewrite_mp_spec_tree skips .sh so they stay
  # path-neutral. The orchestrator passes scripts_dir to the crawl-executor at runtime.
  copy_dir "$SPEC_SRC/skills/app-spec-creator/scripts" "$plugdir/skills/mp-spec/scripts"
  if [ "$tool" = claude ]; then
    for a in "$SPEC_SRC"/agents/*.md; do
      [ -f "$a" ] || continue
      render_md "$a" "$plugdir/agents/$(basename "$a")" "$adir" "$tool"
    done
  fi
  rewrite_mp_spec_tree "$plugdir" "$tool"
}

# ----- mp-dev (Claude-only): de-specialize templates into a generic /mp plugin ------------------

# Write the reusable snippets (preamble + reviewer resolver) once, as files, so awk can splice them
# in with getline — far safer than inline-escaping bash inside awk print statements.
write_dev_snippets() {
  PREAMBLE_FILE="$WORK/preamble.md"
  RESOLVER_FILE="$WORK/resolver.sh"
  cat > "$PREAMBLE_FILE" <<'EOF'

> **mp-dev — project config (read first).** This agent is project-agnostic. Resolve project
> specifics at runtime: read `.claude/mp/config.json` (`package`, `packagePath`, `platforms`,
> `sourceRoot`, `stack`, `uiLang`, `projectName`) and the repo-root `CLAUDE.md` for stack/architecture.
> If `.claude/mp/extras/<this-agent-name>.md` exists, read it **after** this file — its
> project-specific rules win on conflict. Tokens `<package>` / `<pkg-path>` below are `config.json`
> values (`package` / `packagePath`).
EOF
  cat > "$RESOLVER_FILE" <<'EOF'

# package + source root resolved at runtime from the mp-dev project config
CONFIG="$REPO_ROOT/.claude/mp/config.json"
_mpcfg() { grep -oE "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" "$CONFIG" 2>/dev/null | head -1 | sed -E 's/.*:[[:space:]]*"([^"]*)".*/\1/'; }
PACKAGE="$(_mpcfg package)"
SRC_ROOT="app/src/main/java/$(_mpcfg packagePath)"
if [ -z "$PACKAGE" ] || [ -z "$SRC_ROOT" ]; then
  printf '%s\n' '{"pass":false,"violations":["missing or invalid .claude/mp/config.json (need package + packagePath)"]}'
  exit 0
fi
EOF
}

# transform_dev_md <src> <dst> <is_agent:0|1>
transform_dev_md() {
  local src="$1" dst="$2" is_agent="$3" tmp
  if [ "$DRY" = 1 ]; then echo "  [dry] dev-md ${src#"$ROOT"/} -> ${dst#"$ROOT"/}"; return; fi
  mkdir -p "$(dirname "$dst")"
  tmp="$(mktemp)"
  sed -e 's#{{PREFIX}}#mp#g' \
      -e 's#the {{PROJECT_NAME}}#the project#g' \
      -e 's#The {{PROJECT_NAME}}#The project#g' \
      -e 's#{{PROJECT_NAME}}#the project#g' \
      -e "s#{{UI_LANGUAGE}}#the project's configured UI language#g" \
      -e 's#{{PACKAGE_PATH}}#<pkg-path>#g' \
      -e 's#{{PACKAGE}}#<package>#g' \
      -e 's#{{PLATFORM}}#android#g' \
      -e 's#{{AGENT_DIR}}#.claude#g' \
      -e 's#\.claude/scripts/#${CLAUDE_PLUGIN_ROOT}/scripts/#g' \
      -e 's#\.claude/\.cmp-version#.claude/mp/config.json#g' \
      "$src" \
    | sed "/<!-- tool:codex -->/,/<!-- \/tool:codex -->/d" \
    | sed -e "/<!-- tool:claude -->/d" -e "/<!-- \/tool:claude -->/d" \
    > "$tmp"
  mv "$tmp" "$dst"
  strip_platform_block   "$dst" ios
  strip_platform_markers "$dst" android
  strip_if_markers       "$dst"
  if [ "$is_agent" = 1 ]; then
    tmp="$(mktemp)"
    awk -v pf="$PREAMBLE_FILE" 'BEGIN{c=0} {print} /^---[[:space:]]*$/{c++; if(c==2){while((getline l < pf)>0) print l}}' "$dst" > "$tmp"
    mv "$tmp" "$dst"
  fi
}

# Runtime router/runbooks are shared by both harnesses. Unlike agent transformation above, this
# helper keeps the selected tool branch and resolves script paths for that harness.
transform_dev_runtime_md() {
  local src="$1" dst="$2" tool="$3" agentdir other script_root tmp
  if [ "$tool" = claude ]; then
    agentdir=".claude"
    other="codex"
    script_root='${CLAUDE_PLUGIN_ROOT}/scripts/'
  else
    agentdir=".codex"
    other="claude"
    script_root='$MP_SCRIPTS/'
  fi
  if [ "$DRY" = 1 ]; then
    echo "  [dry] runtime $(basename "$src") -> ${dst#"$ROOT"/} ($tool)"
    return
  fi
  mkdir -p "$(dirname "$dst")"
  tmp="$(mktemp)"
  sed -e 's#{{PREFIX}}#mp#g' \
      -e 's#the {{PROJECT_NAME}}#the project#g' \
      -e 's#The {{PROJECT_NAME}}#The project#g' \
      -e 's#{{PROJECT_NAME}}#the project#g' \
      -e "s#{{UI_LANGUAGE}}#the project's configured UI language#g" \
      -e 's#{{PACKAGE_PATH}}#<pkg-path>#g' \
      -e 's#{{PACKAGE}}#<package>#g' \
      -e 's#{{PLATFORM}}#android#g' \
      -e "s#{{AGENT_DIR}}#${agentdir}#g" \
      -e "s#\.claude/scripts/#${script_root}#g" \
      -e "s#\.codex/scripts/#${script_root}#g" \
      -e 's#\.claude/\.cmp-version#.claude/mp/config.json#g' \
      "$src" \
    | sed "/<!-- tool:${other} -->/,/<!-- \/tool:${other} -->/d" \
    | sed -e "/<!-- tool:claude -->/d" -e "/<!-- \/tool:claude -->/d" \
          -e "/<!-- tool:codex -->/d"  -e "/<!-- \/tool:codex -->/d" \
    > "$tmp"
  mv "$tmp" "$dst"
  strip_platform_block   "$dst" ios
  strip_platform_markers "$dst" android
  strip_if_markers       "$dst"

  if [ "$(basename "$src")" = "contract-startup.md" ]; then
    tmp="$(mktemp)"
    sed -e 's#^1\. Read `CLAUDE.md` (at the repository root) for tech stack and architecture\.#1. Read `.claude/mp/config.json` (package, platforms, sourceRoot, stack, uiLang) and `CLAUDE.md` for tech stack/architecture, plus any `.claude/mp/extras/*.md` project overrides.#' \
        "$dst" > "$tmp"
    mv "$tmp" "$dst"
  fi
}

# transform_dev_command <src> <dst>
transform_dev_command() {
  local src="$1" dst="$2" tmp body
  transform_dev_md "$src" "$dst" 0
  [ "$DRY" = 1 ] && return 0
  # augment the Startup step to read the runtime config + extras
  tmp="$(mktemp)"
  sed -e 's#^1\. Read `CLAUDE.md` (at the repository root) for tech stack and architecture\.#1. Read `.claude/mp/config.json` (package, platforms, sourceRoot, stack, uiLang) and `CLAUDE.md` for tech stack/architecture, plus any `.claude/mp/extras/*.md` project overrides.#' \
      "$dst" > "$tmp"
  mv "$tmp" "$dst"
  # prepend command frontmatter (commands support description metadata; silences validate warning)
  body="$WORK/command-body-$$.md"; mv "$dst" "$body"
  {
    printf '%s\n' '---'
    printf '%s\n' 'description: Mobile dev orchestrator (/mp) — runs the SPEC → develop → review → test → verify pipeline (Android/iOS, Clean Architecture). Reads .claude/mp/config.json + CLAUDE.md + .claude/mp/extras for project specifics.'
    printf '%s\n' 'argument-hint: --feature|--bugfix|--discuss|--spec|--coverage|--upgrade|--device|--fit|--plan|--phase|--check|--continue|--improve|--reflect|--deliver <args>'
    printf '%s\n' '---'
    cat "$body"
  } > "$dst"
}

# transform_dev_script <src> <dst> <kind:runner|reviewer>
transform_dev_script() {
  local src="$1" dst="$2" kind="$3" tmp
  if [ "$DRY" = 1 ]; then echo "  [dry] dev-sh ${src#"$ROOT"/} -> ${dst#"$ROOT"/} ($kind)"; return; fi
  mkdir -p "$(dirname "$dst")"
  tmp="$(mktemp)"
  sed -e 's#{{PREFIX}}#mp#g' -e 's#{{PROJECT_NAME}}#the project#g' "$src" > "$tmp"
  mv "$tmp" "$dst"
  if [ "$kind" = reviewer ]; then
    tmp="$(mktemp)"
    sed -e '/^PACKAGE="{{PACKAGE}}"$/d' -e '\#^SRC_ROOT="app/src/main/java/{{PACKAGE_PATH}}"$#d' "$dst" > "$tmp"
    mv "$tmp" "$dst"
    tmp="$(mktemp)"
    awk -v rf="$RESOLVER_FILE" 'BEGIN{done=0} {print} /^cd "\$REPO_ROOT"$/ && !done {while((getline l < rf)>0) print l; done=1}' "$dst" > "$tmp"
    mv "$tmp" "$dst"
  fi
  chmod +x "$dst" 2>/dev/null || true
}

build_mp_dev() {
  local plugdir="$ROOT/claude-plugins/mp-dev" f base rv runtime_dir
  echo "==> mp-dev (claude, android) -> ${plugdir#"$ROOT"/}"
  [ "$DRY" = 1 ] || write_dev_snippets

  for base in architect docs maintainer intake knowledge planner phase-planner improve reflect; do
    transform_dev_md "$COMMON/agents/{{PREFIX}}-$base.md" "$plugdir/agents/mp-$base.md" 1
  done

  # Reviewer = reviewer-base + android overlay (assemble, then transform once).
  if [ "$DRY" = 1 ]; then
    echo "  [dry] assemble reviewer-base + android overlay -> claude-plugins/mp-dev/agents/mp-reviewer-android.md"
  else
    rv="$WORK/reviewer-source-$$.md"
    cat "$COMMON/agents/{{PREFIX}}-reviewer-base.md" > "$rv"
    printf '\n' >> "$rv"
    cat "$ANDROID/agents/{{PREFIX}}-reviewer-android.md" >> "$rv"
    transform_dev_md "$rv" "$plugdir/agents/mp-reviewer-android.md" 1
  fi

  # Android specialist agents (skip the reviewer overlay — handled above).
  for f in "$ANDROID"/agents/*.md; do
    base="$(basename "$f")"
    [ "$base" = "{{PREFIX}}-reviewer-android.md" ] && continue
    transform_dev_md "$f" "$plugdir/agents/${base/\{\{PREFIX\}\}/mp}" 1
  done

  transform_dev_command "$COMMON/commands/{{PREFIX}}.md" "$plugdir/commands/mp.md"

  runtime_dir="$plugdir/commands/mp-runtime"
  for f in "$COMMON"/commands/runtime/*.md; do
    [ -f "$f" ] || continue
    transform_dev_runtime_md "$f" "$runtime_dir/$(basename "$f")" claude
  done
  if [ "$DRY" = 1 ]; then
    echo "  [dry] copy   templates/common/commands/runtime/manifest.tsv -> claude-plugins/mp-dev/commands/mp-runtime/manifest.tsv"
  else
    mkdir -p "$runtime_dir"
    cp "$COMMON/commands/runtime/manifest.tsv" "$runtime_dir/manifest.tsv"
  fi

  transform_dev_script "$ANDROID/scripts/{{PREFIX}}-runner-android.sh"   "$plugdir/scripts/mp-runner-android.sh"   runner
  transform_dev_script "$ANDROID/scripts/{{PREFIX}}-reviewer-android.sh" "$plugdir/scripts/mp-reviewer-android.sh" reviewer

  # Common (platform-neutral) scripts — e.g. the improvement → PR helper.
  if [ -d "$COMMON/scripts" ]; then
    for s in "$COMMON"/scripts/*.sh; do
      [ -f "$s" ] || continue
      base="$(basename "$s")"
      transform_dev_script "$s" "$plugdir/scripts/${base/\{\{PREFIX\}\}/mp}" neutral
    done
  fi
}

build_mp_dev_codex() {
  local plugdir="$ROOT/codex-plugins/mp-dev" runtime_dir scripts_dir f s base
  echo "==> mp-dev (codex) -> ${plugdir#"$ROOT"/}"
  if [ "$DRY" = 1 ]; then
    echo "  [dry] copy   ${DEV_CODEX#"$ROOT"/}/.codex-plugin -> ${plugdir#"$ROOT"/}/.codex-plugin"
    echo "  [dry] copy   ${DEV_CODEX#"$ROOT"/}/skills/mp-dev -> ${plugdir#"$ROOT"/}/skills/mp-dev"
    transform_dev_runtime_md "$COMMON/commands/{{PREFIX}}.md" "$plugdir/skills/mp-dev/references/runtime/router.md" codex
    for f in "$COMMON"/commands/runtime/*.md; do
      [ -f "$f" ] || continue
      transform_dev_runtime_md "$f" "$plugdir/skills/mp-dev/references/runtime/$(basename "$f")" codex
    done
    echo "  [dry] copy   templates/common/commands/runtime/manifest.tsv -> codex-plugins/mp-dev/skills/mp-dev/references/runtime/manifest.tsv"
    transform_dev_script "$ANDROID/scripts/{{PREFIX}}-runner-android.sh" "$plugdir/skills/mp-dev/scripts/mp-runner-android.sh" runner
    transform_dev_script "$ANDROID/scripts/{{PREFIX}}-reviewer-android.sh" "$plugdir/skills/mp-dev/scripts/mp-reviewer-android.sh" reviewer
    for s in "$COMMON"/scripts/*.sh; do
      [ -f "$s" ] || continue
      base="$(basename "$s")"
      transform_dev_script "$s" "$plugdir/skills/mp-dev/scripts/${base/\{\{PREFIX\}\}/mp}" neutral
    done
    return 0
  fi
  mkdir -p "$plugdir"
  copy_dir "$DEV_CODEX/.codex-plugin" "$plugdir/.codex-plugin"
  copy_dir "$DEV_CODEX/skills/mp-dev" "$plugdir/skills/mp-dev"

  runtime_dir="$plugdir/skills/mp-dev/references/runtime"
  transform_dev_runtime_md "$COMMON/commands/{{PREFIX}}.md" "$runtime_dir/router.md" codex
  for f in "$COMMON"/commands/runtime/*.md; do
    [ -f "$f" ] || continue
    transform_dev_runtime_md "$f" "$runtime_dir/$(basename "$f")" codex
  done
  cp "$COMMON/commands/runtime/manifest.tsv" "$runtime_dir/manifest.tsv"

  scripts_dir="$plugdir/skills/mp-dev/scripts"
  transform_dev_script "$ANDROID/scripts/{{PREFIX}}-runner-android.sh" "$scripts_dir/mp-runner-android.sh" runner
  transform_dev_script "$ANDROID/scripts/{{PREFIX}}-reviewer-android.sh" "$scripts_dir/mp-reviewer-android.sh" reviewer
  for s in "$COMMON"/scripts/*.sh; do
    [ -f "$s" ] || continue
    base="$(basename "$s")"
    transform_dev_script "$s" "$scripts_dir/${base/\{\{PREFIX\}\}/mp}" neutral
  done
}

validate_dev_runtime() {
  local runtime="$COMMON/commands/runtime"
  local router="$COMMON/commands/{{PREFIX}}.md"
  local manifest="$runtime/manifest.tsv"
  local expected_modes mode selector runbook file contracts contract seen_modes seen_runbooks count
  local flag heading bytes base

  expected_modes="feature bugfix discuss spec coverage upgrade device fit plan phase check continue improve reflect deliver"
  [ -f "$router" ] || { echo "runtime-check: missing router: $router" >&2; return 1; }
  [ -f "$manifest" ] || { echo "runtime-check: missing manifest: $manifest" >&2; return 1; }
  [ -f "$runtime/coverage-headings.txt" ] || {
    echo "runtime-check: missing pre-split heading inventory" >&2
    return 1
  }

  bytes="$(wc -c < "$router" | tr -d '[:space:]')"
  [ "$bytes" -le 12000 ] || {
    echo "runtime-check: router exceeds 12000-byte fixed-context budget ($bytes)" >&2
    return 1
  }
  if grep -q '^## Workflow:' "$router"; then
    echo "runtime-check: workflow body leaked back into the compact router" >&2
    return 1
  fi

  seen_modes=""
  seen_runbooks=""
  count=0
  while IFS=$'\t' read -r mode selector runbook; do
    case "$mode" in ""|'#'*) continue ;; esac
    case " $expected_modes " in
      *" $mode "*) ;;
      *) echo "runtime-check: unknown mode in manifest: $mode" >&2; return 1 ;;
    esac
    if printf '%s\n' "$seen_modes" | grep -Fxq -- "$mode"; then
      echo "runtime-check: duplicate mode in manifest: $mode" >&2
      return 1
    fi
    seen_modes="$(printf '%s\n%s' "$seen_modes" "$mode")"
    seen_runbooks="$(printf '%s\n%s' "$seen_runbooks" "$runbook")"
    count=$((count + 1))

    file="$runtime/$runbook"
    [ -f "$file" ] || { echo "runtime-check: missing runbook: $runbook" >&2; return 1; }
    grep -Fq -- "<!-- mp-runtime-mode: $mode -->" "$file" || {
      echo "runtime-check: mode metadata mismatch: $runbook" >&2
      return 1
    }
    grep -Fq -- "## Workflow: $selector" "$file" || {
      echo "runtime-check: workflow heading missing for $selector in $runbook" >&2
      return 1
    }
    grep -Fq -- "$selector" "$router" && grep -Fq -- "$runbook" "$router" || {
      echo "runtime-check: router dispatch missing $selector -> $runbook" >&2
      return 1
    }

    contracts="$(sed -n 's/^<!-- mp-runtime-contracts: \(.*\) -->$/\1/p' "$file")"
    [ -n "$contracts" ] || {
      echo "runtime-check: contracts metadata missing: $runbook" >&2
      return 1
    }
    for contract in $contracts; do
      [ -f "$runtime/contract-$contract.md" ] || {
        echo "runtime-check: $runbook references missing contract-$contract.md" >&2
        return 1
      }
      grep -Fq -- "<!-- mp-runtime-contract: $contract -->" "$runtime/contract-$contract.md" || {
        echo "runtime-check: contract marker mismatch: contract-$contract.md" >&2
        return 1
      }
    done
  done < "$manifest"

  [ "$count" -eq 15 ] || {
    echo "runtime-check: expected 15 modes, found $count" >&2
    return 1
  }
  for mode in $expected_modes; do
    printf '%s\n' "$seen_modes" | grep -Fxq -- "$mode" || {
      echo "runtime-check: mode lost from manifest: $mode" >&2
      return 1
    }
  done

  for file in "$runtime"/*.md; do
    base="$(basename "$file")"
    case "$base" in contract-*.md) continue ;; esac
    printf '%s\n' "$seen_runbooks" | grep -Fxq -- "$base" || {
      echo "runtime-check: orphan runbook not in manifest: $base" >&2
      return 1
    }
  done

  for contract in execution telemetry platform device startup risk-routing feature-implementation post-ship backlog \
    rules rules-board rules-implementation rules-learning rules-fit
  do
    [ -f "$runtime/contract-$contract.md" ] || {
      echo "runtime-check: required shared contract lost: $contract" >&2
      return 1
    }
  done

  count="$(grep -h '^- ' "$runtime"/contract-rules*.md | wc -l | tr -d '[:space:]')"
  [ "$count" -eq 31 ] || {
    echo "runtime-check: expected 31 preserved rule bullets, found $count" >&2
    return 1
  }

  for heading in \
    "## Deterministic steps via" \
    "## Strict output contracts" \
    "## Run telemetry" \
    "## Platform resolution" \
    "## Visual autotest device pre-flight" \
    "## Startup" \
    "### Phase 2 — Implement" \
    "## Post-ship" \
    "## SPEC backlog board" \
    "## Rules"
  do
    grep -R -Fq -- "$heading" "$runtime" || {
      echo "runtime-check: shared heading lost: $heading" >&2
      return 1
    }
  done

  while IFS= read -r heading; do
    [ -n "$heading" ] || continue
    grep -Fqx -- "$heading" "$router" "$runtime"/*.md || {
      echo "runtime-check: heading lost during split: $heading" >&2
      return 1
    }
  done < "$runtime/coverage-headings.txt"

  # Snapshot of every flag token in the pre-split command. This catches silent losses while allowing
  # a flag to move between a mode runbook and its declared contract.
  for flag in \
    --agent --backlog --bootstrap --bugfix --built --check --continue --cost --coverage \
    --deliver --device --discuss --drain --feature --fit --format --from --improve --login \
    --metric --model --name-status --next --note --out --phase --phases --plan --reference \
    --reflect --retry --show-toplevel --spec --sync --target --tdd --tokens-in --tokens-out \
    --tokens-cached --tokens-reasoning --cost-usd --duration-ms --correlation-id --upgrade --verdict
  do
    grep -R -Fq -- "$flag" "$router" "$runtime" || {
      echo "runtime-check: flag lost during split: $flag" >&2
      return 1
    }
  done

  echo "runtime-check: pass (15 modes, 14 contracts, router=${bytes}B)"
}

validate_dev_runtime
if [ "$CHECK_RUNTIME" = 1 ]; then
  exit 0
fi

if [ "$DRY" = 0 ]; then
  build_stamp="$(date -u +%Y%m%dT%H%M%SZ)-$$"
  ARCHIVE_DIR="$ROOT/archive/marketplace/$build_stamp"
  WORK="$ARCHIVE_DIR/work"
  mkdir -p "$WORK"
  for generated in \
    "$ROOT/claude-plugins/mp-spec/agents" \
    "$ROOT/claude-plugins/mp-spec/skills" \
    "$ROOT/codex-plugins/mp-spec/skills" \
    "$ROOT/claude-plugins/mp-dev/agents" \
    "$ROOT/claude-plugins/mp-dev/commands" \
    "$ROOT/claude-plugins/mp-dev/scripts" \
    "$ROOT/codex-plugins/mp-dev/.codex-plugin" \
    "$ROOT/codex-plugins/mp-dev/skills"
  do
    archive_existing "$generated" previous
  done
fi

build_mp_spec claude
build_mp_spec codex
build_mp_dev
build_mp_dev_codex
sync_manifest_versions

if [ "$DRY" = 1 ]; then
  echo "build-marketplace: done (dry-run mp-spec + mp-dev, v$CMP_VERSION)."
else
  echo "build-marketplace: done (wrote mp-spec + mp-dev, v$CMP_VERSION; previous tree: ${ARCHIVE_DIR#"$ROOT"/})."
fi
