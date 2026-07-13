#!/usr/bin/env bash
# bootstrap.sh — generate a Claude Code mobile pipeline (.claude/ + STATE/ROADMAP/etc)
# from cmp templates into the current directory.
#
# Usage: see docs/USAGE.md, or pass --help to print it.
# Cross-platform: Linux, macOS, Windows Git Bash.

set -e

# ----- locate self & source libs -----------------------------------------
SCRIPT_PATH="${BASH_SOURCE[0]:-$0}"
TEMPLATES_ROOT=$(cd "$(dirname "$SCRIPT_PATH")" && pwd)
LIB_DIR="$TEMPLATES_ROOT/lib"

# shellcheck source=lib/detect.sh
. "$LIB_DIR/detect.sh"
# shellcheck source=lib/prompts.sh
. "$LIB_DIR/prompts.sh"
# shellcheck source=lib/render.sh
. "$LIB_DIR/render.sh"

# ----- parse args --------------------------------------------------------
PLATFORM=""
PREFIX=""
PROJECT_NAME=""
PROJECT_DESCRIPTION=""
PACKAGE=""
UI_LANG="en"
MEMORY_PATH=""
ARCH="clean"
FORCE=0
DRY_RUN=0
SKIP_MEMORY=0
NON_INTERACTIVE=0
NO_GIT=0

while [ $# -gt 0 ]; do
    case "$1" in
        --platform=*)            PLATFORM="${1#*=}" ;;
        --prefix=*)              PREFIX="${1#*=}" ;;
        --project-name=*)        PROJECT_NAME="${1#*=}" ;;
        --project-description=*) PROJECT_DESCRIPTION="${1#*=}" ;;
        --package=*)             PACKAGE="${1#*=}" ;;
        --ui-lang=*)             UI_LANG="${1#*=}" ;;
        --memory-path=*)         MEMORY_PATH="${1#*=}" ;;
        --arch=*)                ARCH="${1#*=}" ;;
        --force)                 FORCE=1 ;;
        --dry-run)               DRY_RUN=1 ;;
        --skip-memory)           SKIP_MEMORY=1 ;;
        --non-interactive)       NON_INTERACTIVE=1 ;;
        --no-git)                NO_GIT=1 ;;
        --help|-h)               cat "$TEMPLATES_ROOT/docs/USAGE.md"; exit 0 ;;
        *) echo "Unknown flag: $1 (use --help)" >&2; exit 1 ;;
    esac
    shift
done

# ----- interactive prompts if required flags missing ---------------------
maybe_prompt() {
    local current="$1" name="$2" pattern="${3:-.+}"
    if [ -z "$current" ]; then
        if [ "$NON_INTERACTIVE" -eq 1 ]; then
            echo "Missing required: --${name}" >&2; exit 1
        fi
        prompt_required "$name" "$pattern"
    else
        printf '%s' "$current"
    fi
}

PLATFORM=$(maybe_prompt "$PLATFORM" "platform (android|ios|android,ios)" "^(android|ios)(,(android|ios))*$")
PREFIX=$(maybe_prompt "$PREFIX" "prefix" "^[a-z][a-z0-9_]{0,7}$")
PROJECT_NAME=$(maybe_prompt "$PROJECT_NAME" "project-name")

# package required only if android in platforms
case ",$PLATFORM," in
    *,android,*)
        PACKAGE=$(maybe_prompt "$PACKAGE" "package" "^[a-z]+(\.[a-z][a-z0-9_]*)+$")
        ;;
esac

[ -z "$PROJECT_DESCRIPTION" ] && PROJECT_DESCRIPTION="(One-sentence project description — replace this placeholder.)"

# ----- validate ----------------------------------------------------------
case "$PREFIX" in
    init|clear|help|model|config|cost|review|security-review|loop|schedule|simplify)
        echo "Prefix '$PREFIX' conflicts with a built-in command — pick another." >&2; exit 1 ;;
esac

# Warn if not in a git repo
if [ "$NO_GIT" -ne 1 ] && ! is_git_repo .; then
    echo "Warning: current directory is not a git repo." >&2
    echo "  The pipeline can still bootstrap, but push step won't work without git init." >&2
fi

# ----- derive vars -------------------------------------------------------
PACKAGE_PATH=$(printf '%s' "$PACKAGE" | tr '.' '/')
SANITISED_CWD=$(sanitise_path "$(pwd)")
[ -z "$MEMORY_PATH" ] && MEMORY_PATH="$HOME/.claude/projects/$SANITISED_CWD/memory"
TODAY=$(date +%Y-%m-%d)
CMP_VERSION=$(tr -d '[:space:]' < "$TEMPLATES_ROOT/VERSION")
PLATFORMS_LIST=$(printf '%s' "$PLATFORM" | tr ',' ' ')
PRIMARY_PLATFORM=$(printf '%s' "$PLATFORMS_LIST" | awk '{print $1}')
AGENT_DIR=".claude"

case "$PRIMARY_PLATFORM" in
    android) PROJECT_SOURCE_ROOT="app/src/main/java/$PACKAGE_PATH" ;;
    ios)     PROJECT_SOURCE_ROOT="$PROJECT_NAME/Sources" ;;
esac

# ----- preflight ---------------------------------------------------------
if [ "$FORCE" -ne 1 ]; then
    for path in .claude CLAUDE.md STATE.md ROADMAP.md DOCUMENTATION.md; do
        if [ -e "$path" ]; then
            echo "Existing $path — use --force to overwrite." >&2; exit 2
        fi
    done
fi

# ----- dry-run preview ---------------------------------------------------
if [ "$DRY_RUN" -eq 1 ]; then
    echo "DRY RUN — would create:"
    echo "  .claude/agents/$PREFIX-{architect,docs,reviewer-<plat>,developer-<plat>,tester-<plat>,verifier-<plat>,runner-<plat>}.md"
    echo "  .claude/agents/$PREFIX-coverage-android.md   (android-only, opt-in /coverage agent)"
    echo "  .claude/agents/$PREFIX-ui-designer-android.md (android-only)"
    echo "  .claude/agents/$PREFIX-runner-instrumented-android.md (android-only, on-device /$PREFIX --device runner)"
    echo "  .claude/commands/$PREFIX.md"
    echo "  .claude/commands/$PREFIX-runtime/*.md   (lazy-loaded mode contracts)"
    echo "  .claude/scripts/$PREFIX-*.sh            (common + platform helpers)"
    echo "  .claude/specs/README.md"
    echo "  .claude/specs/{backlog,active,done}/.gitkeep   (SPEC backlog board)"
    echo "  .claude/.cmp-version"
    echo "  ./CLAUDE.md ./STATE.md ./ROADMAP.md ./DOCUMENTATION.md"
    [ "$SKIP_MEMORY" -ne 1 ] && echo "  $MEMORY_PATH/MEMORY.md + memos"
    echo ""
    echo "Vars resolved:"
    echo "  platforms=$PLATFORM  prefix=$PREFIX  package=$PACKAGE  ui-lang=$UI_LANG"
    exit 0
fi

# ----- build vars file for render_file ----------------------------------
VARS_FILE=$(mktemp)
trap 'rm -f "$VARS_FILE"' EXIT
cat > "$VARS_FILE" <<EOF
PREFIX=$PREFIX
PROJECT_NAME=$PROJECT_NAME
PROJECT_DESCRIPTION=$PROJECT_DESCRIPTION
PACKAGE=$PACKAGE
PACKAGE_PATH=$PACKAGE_PATH
PLATFORM=$PRIMARY_PLATFORM
PROJECT_SOURCE_ROOT=$PROJECT_SOURCE_ROOT
UI_LANGUAGE=$UI_LANG
MEMORY_PATH=$MEMORY_PATH
TODAY=$TODAY
CMP_VERSION=$CMP_VERSION
AGENT_DIR=$AGENT_DIR
EOF

# ----- copy_phase --------------------------------------------------------
mkdir -p .claude/agents ".claude/commands/$PREFIX-runtime" .claude/specs .claude/scripts

# 1. Common agents (architect, docs — direct copy; reviewer-base handled per-platform)
for src in "$TEMPLATES_ROOT"/templates/common/agents/*.md; do
    base=$(basename "$src")
    case "$base" in
        '{{PREFIX}}-reviewer-base.md')
            # Assemble per platform: base + platform overlay
            for plat in $PLATFORMS_LIST; do
                overlay="$TEMPLATES_ROOT/templates/$plat/agents/{{PREFIX}}-reviewer-$plat.md"
                if [ -f "$overlay" ]; then
                    dst=".claude/agents/{{PREFIX}}-reviewer-$plat.md"
                    cp "$src" "$dst"
                    echo "" >> "$dst"
                    cat "$overlay" >> "$dst"
                fi
            done
            ;;
        *)
            cp "$src" ".claude/agents/$base"
            ;;
    esac
done

# 2. Common command
cp "$TEMPLATES_ROOT/templates/common/commands/{{PREFIX}}.md" \
   ".claude/commands/{{PREFIX}}.md"

# 2b. Lazy-loaded command contracts. The compact router reads only the selected mode file.
if [ -d "$TEMPLATES_ROOT/templates/common/commands/runtime" ]; then
    for src in "$TEMPLATES_ROOT"/templates/common/commands/runtime/*.md; do
        [ -f "$src" ] || continue
        cp "$src" ".claude/commands/$PREFIX-runtime/$(basename "$src")"
    done
    if [ -f "$TEMPLATES_ROOT/templates/common/commands/runtime/manifest.tsv" ]; then
        cp "$TEMPLATES_ROOT/templates/common/commands/runtime/manifest.tsv" \
           ".claude/commands/$PREFIX-runtime/manifest.tsv"
    fi
fi

# 3. Common specs/README + the SPEC backlog board folders (backlog/active/done)
cp "$TEMPLATES_ROOT/templates/common/specs/README.md" \
   ".claude/specs/README.md"
mkdir -p .claude/specs/backlog .claude/specs/active .claude/specs/done
for board in backlog active done; do
    cp "$TEMPLATES_ROOT/templates/common/specs/$board/.gitkeep" \
       ".claude/specs/$board/.gitkeep"
done

# 4. Platform agents (skip reviewer-<plat> — already handled above)
for plat in $PLATFORMS_LIST; do
    for src in "$TEMPLATES_ROOT"/templates/"$plat"/agents/*.md; do
        base=$(basename "$src")
        [ "$base" = "{{PREFIX}}-reviewer-$plat.md" ] && continue
        cp "$src" ".claude/agents/$base"
    done
done

# 4b. Platform scripts (.sh) — runner/reviewer deterministic helpers.
for plat in $PLATFORMS_LIST; do
    [ -d "$TEMPLATES_ROOT/templates/$plat/scripts" ] || continue
    for src in "$TEMPLATES_ROOT"/templates/"$plat"/scripts/*.sh; do
        [ -f "$src" ] || continue
        base=$(basename "$src")
        cp "$src" ".claude/scripts/$base"
        chmod +x ".claude/scripts/$base"
    done
done

# 4c. Common scripts (risk routing, telemetry, brain inbox, improvement lifecycle, delivery).
if [ -d "$TEMPLATES_ROOT/templates/common/scripts" ]; then
    for src in "$TEMPLATES_ROOT"/templates/common/scripts/*.sh; do
        [ -f "$src" ] || continue
        base=$(basename "$src")
        cp "$src" ".claude/scripts/$base"
        chmod +x ".claude/scripts/$base"
    done
fi

# 5. Root templates (.tmpl → strip extension)
for src in "$TEMPLATES_ROOT"/templates/common/root/*.md.tmpl; do
    base=$(basename "$src" .tmpl)
    cp "$src" "./$base"
done

# ----- render_phase: placeholders ---------------------------------------
ROOT_FILES="./CLAUDE.md ./STATE.md ./ROADMAP.md ./DOCUMENTATION.md"
for f in .claude/agents/*.md .claude/commands/*.md .claude/commands/*/*.md .claude/specs/*.md .claude/scripts/*.sh $ROOT_FILES; do
    [ -f "$f" ] || continue
    render_file "$f" "$VARS_FILE"
done

# ----- render_phase: conditional blocks (platform + if) -----------------
ALL_PLATFORMS="android ios"
strip_conditionals() {
    local f="$1"
    for plat in $ALL_PLATFORMS; do
        local in_list=0
        for sel in $PLATFORMS_LIST; do
            [ "$plat" = "$sel" ] && in_list=1
        done
        if [ "$in_list" -eq 1 ]; then
            strip_platform_markers "$f" "$plat"
        else
            strip_platform_block "$f" "$plat"
        fi
    done
    # bootstrap.sh currently emits the canonical Claude adapter.
    strip_tool_block "$f" codex
    strip_tool_markers "$f" claude
    # UI_LANGUAGE conditionals
    if [ "$UI_LANG" = "en" ]; then
        strip_if_block "$f" "UI_LANGUAGE != en"
    else
        strip_if_block "$f" "UI_LANGUAGE == en"
    fi
    # 'if learning' block — keep for now (user can edit)
    strip_if_markers "$f"
}

for f in .claude/agents/*.md .claude/commands/*.md .claude/commands/*/*.md $ROOT_FILES; do
    [ -f "$f" ] || continue
    strip_conditionals "$f"
done

# ----- rename files: {{PREFIX}} in basename -----------------------------
# Must happen after content rendering so file contents already have PREFIX substituted.
for f in .claude/agents/*.md .claude/commands/*.md .claude/commands/*/*.md .claude/scripts/*.sh; do
    [ -f "$f" ] || continue
    base=$(basename "$f")
    if [[ "$base" == *'{{PREFIX}}'* ]]; then
        new_base="${base//\{\{PREFIX\}\}/$PREFIX}"
        mv "$f" "$(dirname "$f")/$new_base"
    fi
done

# ----- memory_phase -----------------------------------------------------
if [ "$SKIP_MEMORY" -ne 1 ]; then
    mkdir -p "$MEMORY_PATH"
    # Common memos
    for src in "$TEMPLATES_ROOT"/templates/common/memory/*.md.tmpl; do
        base=$(basename "$src" .tmpl)
        dst="$MEMORY_PATH/$base"
        [ -f "$dst" ] && continue   # never overwrite existing memory
        cp "$src" "$dst"
        render_file "$dst" "$VARS_FILE"
        strip_conditionals "$dst"
    done
    # Per-platform memos
    for plat in $PLATFORMS_LIST; do
        for src in "$TEMPLATES_ROOT"/templates/"$plat"/memory/*.md.tmpl; do
            [ -f "$src" ] || continue
            base=$(basename "$src" .tmpl)
            dst="$MEMORY_PATH/$base"
            [ -f "$dst" ] && continue
            cp "$src" "$dst"
            render_file "$dst" "$VARS_FILE"
            strip_conditionals "$dst"
        done
    done
    # Regenerate MEMORY.md index from description: frontmatter
    {
        for f in "$MEMORY_PATH"/*.md; do
            [ "$(basename "$f")" = "MEMORY.md" ] && continue
            desc=$(grep -m1 '^description:' "$f" |
                   sed -e 's/^description: *//' -e 's/^"//' -e 's/"$//')
            [ -z "$desc" ] && desc="(no description)"
            echo "- [$desc]($(basename "$f"))"
        done
    } > "$MEMORY_PATH/MEMORY.md"
fi

# ----- version_phase ----------------------------------------------------
cat > .claude/.cmp-version <<EOF
version: $CMP_VERSION
generated: $TODAY
platforms: $PLATFORM
prefix: $PREFIX
package: $PACKAGE
ui-lang: $UI_LANG
EOF

# ----- report -----------------------------------------------------------
echo ""
echo "cmp v$CMP_VERSION bootstrap complete."
echo ""
echo "  Platforms:    $PLATFORM"
echo "  Prefix:       $PREFIX (use /$PREFIX in Claude Code)"
echo "  UI language:  $UI_LANG"
echo "  Memory:       $MEMORY_PATH"
echo ""
agent_count=$(find .claude/agents -name '*.md' | wc -l | tr -d ' ')
memory_count=$([ "$SKIP_MEMORY" -eq 1 ] && echo 0 || find "$MEMORY_PATH" -name '*.md' | wc -l | tr -d ' ')
echo "  Files created:"
echo "    $agent_count agent(s)"
echo "    1 command"
echo "    4 root docs (CLAUDE/STATE/ROADMAP/DOCUMENTATION)"
echo "    $memory_count memory file(s)"
echo ""
echo "Next steps:"
echo "  1. Edit ROADMAP.md → add Iteration 1 goal + items."
echo "  2. Edit CLAUDE.md → fill in any TBD fields for your stack."
echo "  3. Open in Claude Code: /$PREFIX --discuss <topic>  (to brainstorm Iteration 1)"
echo "     or: /$PREFIX --feature <description>  (to start implementing)"
