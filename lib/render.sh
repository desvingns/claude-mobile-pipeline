#!/usr/bin/env bash
# lib/render.sh — placeholder replacement and conditional-block trimming.
# Sourced by bootstrap.sh.
#
# Cross-platform principle: never use `sed -i` (incompatible between GNU sed
# and BSD sed). Always write to a tmp file and `mv`.

# replace_placeholder <file> <key> <value>
# Replaces all `{{KEY}}` occurrences in <file> with <value>.
replace_placeholder() {
    local file="$1" key="$2" value="$3"
    local tmp="${file}.tmp.$$"
    # Escape value for sed replacement side: \, &, and our delimiter |
    local escaped
    escaped=$(printf '%s' "$value" | sed -e 's/[\&|]/\\&/g')
    sed -e "s|{{${key}}}|${escaped}|g" "$file" > "$tmp" && mv "$tmp" "$file"
}

# replace_in_filename <file> <key> <value>
# Renames <file> if its basename contains `{{KEY}}`. Echoes new path.
replace_in_filename() {
    local file="$1" key="$2" value="$3"
    local dir base new_base
    dir=$(dirname "$file")
    base=$(basename "$file")
    new_base="${base//\{\{${key}\}\}/${value}}"
    if [ "$new_base" != "$base" ]; then
        mv "$file" "$dir/$new_base"
        printf '%s' "$dir/$new_base"
    else
        printf '%s' "$file"
    fi
}

# strip_platform_block <file> <platform>
# Deletes `<!-- platform:X --> ... <!-- /platform:X -->` blocks (inclusive of markers).
#
# Handles both inline (open+close on one line) and multi-line forms in two passes:
#   1. `s|...|...|g`         — collapses inline blocks on a single line.
#   2. `/A/,/B/d`            — deletes multi-line ranges after the inline pass
#                              has removed all single-line cases.
#
# This avoids the GNU/BSD sed range pitfall where `/A/,/B/` starts scanning for B
# on the line AFTER A matches — so an inline open+close swallows everything down
# to the next close. Note: greedy `.*` on the inline pass means two inline blocks
# on the same line will be merged into one match; that's an accepted limitation,
# author the templates with at most one inline block per line.
strip_platform_block() {
    local file="$1" platform="$2"
    local tmp="${file}.tmp.$$"
    sed -e "s|<!-- platform:${platform} -->.*<!-- /platform:${platform} -->||g" \
        -e "/<!-- platform:${platform} -->/,/<!-- \/platform:${platform} -->/d" \
        "$file" > "$tmp" && mv "$tmp" "$file"
}

# strip_platform_markers <file> <platform>
# Removes the marker text (keeps wrapped content) — for selected platforms.
# Handles inline markers correctly: replaces the marker substring with nothing
# instead of deleting the whole line, so content on the same line survives.
# Lines that contained ONLY the marker collapse to empty lines (intentional).
strip_platform_markers() {
    local file="$1" platform="$2"
    local tmp="${file}.tmp.$$"
    sed -e "s|<!-- platform:${platform} -->||g" \
        -e "s|<!-- /platform:${platform} -->||g" \
        "$file" > "$tmp" && mv "$tmp" "$file"
}

# strip_tool_block <file> <tool>
# Deletes `<!-- tool:X --> ... <!-- /tool:X -->` blocks for an unselected harness.
# The same one-inline-block-per-line limitation as platform blocks applies.
strip_tool_block() {
    local file="$1" tool="$2"
    local tmp="${file}.tmp.$$"
    sed -e "s|<!-- tool:${tool} -->.*<!-- /tool:${tool} -->||g" \
        -e "/<!-- tool:${tool} -->/,/<!-- \/tool:${tool} -->/d" \
        "$file" > "$tmp" && mv "$tmp" "$file"
}

# strip_tool_markers <file> <tool>
# Keeps the selected harness content and removes only its marker text.
strip_tool_markers() {
    local file="$1" tool="$2"
    local tmp="${file}.tmp.$$"
    sed -e "s|<!-- tool:${tool} -->||g" \
        -e "s|<!-- /tool:${tool} -->||g" \
        "$file" > "$tmp" && mv "$tmp" "$file"
}

# strip_if_block <file> <condition>
# Removes `<!-- if CONDITION -->...<!-- /if -->` blocks. Condition is a literal
# string match (e.g. "UI_LANGUAGE != en").
#
# Two-pass strategy — see strip_platform_block for the rationale. The inline
# pass uses greedy `.*`; at most one inline `<!-- if -->...<!-- /if -->` block
# per line is supported.
strip_if_block() {
    local file="$1" condition="$2"
    local tmp="${file}.tmp.$$"
    sed -e "s|<!-- if ${condition} -->.*<!-- /if -->||g" \
        -e "/<!-- if ${condition} -->/,/<!-- \/if -->/d" \
        "$file" > "$tmp" && mv "$tmp" "$file"
}

# strip_if_markers <file>
# Removes ALL `<!-- if ... -->` and `<!-- /if -->` marker text. Call after
# strip_if_block has removed false branches — leftover markers wrap kept branches.
# Replaces the marker substring with nothing rather than deleting whole lines,
# so inline kept-branch content survives.
strip_if_markers() {
    local file="$1"
    local tmp="${file}.tmp.$$"
    sed -E -e 's|<!-- if [^>]* -->||g' -e 's|<!-- /if -->||g' \
        "$file" > "$tmp" && mv "$tmp" "$file"
}

# render_file <file> <vars_file>
# Applies replace_placeholder for each `KEY=value` line in <vars_file>.
# Lines starting with `#` and blank lines are skipped.
render_file() {
    local file="$1" vars_file="$2"
    local key value
    while IFS='=' read -r key value; do
        case "$key" in
            ''|'#'*) continue ;;
        esac
        replace_placeholder "$file" "$key" "$value"
    done < "$vars_file"
}
