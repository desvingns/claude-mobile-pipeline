#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/render.sh
. "$repo/lib/render.sh"

for function_name in strip_tool_block strip_tool_markers; do
  if ! declare -F "$function_name" >/dev/null 2>&1; then
    printf 'test-render-properties: missing required function %s\n' "$function_name" >&2
    exit 1
  fi
done

work="$(mktemp -d "${TMPDIR:-/tmp}/cmp-render-test.XXXXXX")"
file="$work/conditional.md"
cp "$repo/tests/fixtures/render/conditional.md" "$file"
vars="$work/vars"
printf 'PROJECT_NAME=Demo & QA\nPROJECT_SOURCE_ROOT=app/src/main/java/com/demo|fixture\n' > "$vars"
render_file "$file" "$vars"
strip_platform_block "$file" ios
strip_platform_markers "$file" android
strip_tool_block "$file" claude
strip_tool_markers "$file" codex
strip_if_block "$file" 'UI_LANGUAGE != en'
strip_if_markers "$file"

grep -q 'android-inline' "$file"
grep -q 'android-multiline' "$file"
grep -q 'codex-inline' "$file"
grep -q 'codex-multiline' "$file"
grep -q 'english-inline' "$file"
grep -q 'name=Demo & QA' "$file"
grep -q 'path=app/src/main/java/com/demo|fixture' "$file"
if grep -Eq 'ios-|claude-|non-english|<!--|\{\{' "$file"; then
  echo 'test-render-properties: a removed branch or marker leaked' >&2
  exit 1
fi

# Deterministic fuzz/property sweep. Values and surrounding text vary, while
# every case must preserve the selected branch byte-for-byte and remove the other.
i=1
while [ "$i" -le 50 ]; do
  fuzz="$work/fuzz-$i.md"
  printf 'p%s <!-- platform:android -->keep-platform-%s<!-- /platform:android --> s%s\n' "$i" "$i" "$i" > "$fuzz"
  printf 'p%s <!-- platform:ios -->drop-platform-%s<!-- /platform:ios --> s%s\n' "$i" "$i" "$i" >> "$fuzz"
  printf 't%s <!-- tool:codex -->keep-tool-%s<!-- /tool:codex --> u%s\n' "$i" "$i" "$i" >> "$fuzz"
  printf 't%s <!-- tool:claude -->drop-tool-%s<!-- /tool:claude --> u%s\n' "$i" "$i" "$i" >> "$fuzz"
  printf 'value={{VALUE}}\n' >> "$fuzz"
  fuzz_vars="$work/fuzz-$i.vars"
  printf 'VALUE=case-%s & pipe|segment/%s\n' "$i" "$i" > "$fuzz_vars"
  render_file "$fuzz" "$fuzz_vars"
  strip_platform_block "$fuzz" ios
  strip_platform_markers "$fuzz" android
  strip_tool_block "$fuzz" claude
  strip_tool_markers "$fuzz" codex
  grep -q "keep-platform-$i" "$fuzz"
  grep -q "keep-tool-$i" "$fuzz"
  grep -q "value=case-$i & pipe|segment/$i" "$fuzz"
  if grep -Eq 'drop-platform|drop-tool|<!--|\{\{' "$fuzz"; then
    printf 'test-render-properties: fuzz case %s leaked\n' "$i" >&2
    exit 1
  fi
  i=$((i + 1))
done

name="$work/report-{{PREFIX}}.md"
printf 'fixture\n' > "$name"
renamed="$(replace_in_filename "$name" PREFIX demo)"
[ "$renamed" = "$work/report-demo.md" ]
[ -f "$renamed" ]

# Anchored markers and TSV filenames are CR-sensitive. Keep parser inputs and
# executable scripts LF-only even on core.autocrlf=true Windows checkouts.
for attr_path in \
  lib/build-marketplace.sh \
  templates/common/commands/runtime/manifest.tsv \
  templates/common/commands/runtime/contract-execution.md
do
  git -C "$repo" check-attr eol -- "$attr_path" | grep -q 'eol: lf'
done

printf 'test-render-properties: ok (%s)\n' "$work"
