#!/usr/bin/env bash
# spec-preflight.sh — deterministic bundle checks before the semantic evaluator.
# Usage: spec-preflight.sh <spec-dir> [--clone] [--out <pipeline/eval-preflight.json>]
# Emits exactly one JSON line and optionally publishes the same JSON atomically.
set -uo pipefail

json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"; s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"; s="${s//$'\r'/\\r}"; s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

spec_dir="${1:-}"
[ -n "$spec_dir" ] || {
  printf '%s\n' '{"ok":false,"error":"usage: spec-preflight.sh <spec-dir> [--clone] [--out <file>]"}'
  exit 0
}
shift
clone=false
out=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --clone) clone=true; shift ;;
    --out)
      [ "$#" -ge 2 ] || {
        printf '%s\n' '{"ok":false,"error":"--out requires a path"}'
        exit 0
      }
      out="$2"; shift 2
      ;;
    *)
      printf '{"ok":false,"error":"unknown argument: %s"}\n' "$(json_escape "$1")"
      exit 0
      ;;
  esac
done

blockers=""
blocker_count=0
add_blocker() {
  local item
  item="$(json_escape "$1")"
  [ -n "$blockers" ] && blockers="$blockers,"
  blockers="$blockers\"$item\""
  blocker_count=$((blocker_count + 1))
}

required="00_manifest.yaml constitution.md product-brief.md requirements.md user-stories.md design.md nfr.md a11y.md security-privacy.md analytics.md i18n.md risks.md estimate.md"
required_count=0
for file in $required; do
  required_count=$((required_count + 1))
  [ -s "$spec_dir/$file" ] || add_blocker "missing_or_empty:$file"
done

set -- "$spec_dir"/acceptance/*.feature
feature_count=0
if [ -f "$1" ]; then
  for file in "$@"; do
    [ -s "$file" ] || continue
    feature_count=$((feature_count + 1))
  done
else
  add_blocker "missing:acceptance/*.feature"
fi

fr_ids=""
if [ -f "$spec_dir/requirements.md" ]; then
  fr_ids=$(grep -E '^- \*\*FR-[0-9]+\*\*' "$spec_dir/requirements.md" 2>/dev/null \
    | grep -Eo 'FR-[0-9]+' | LC_ALL=C sort || true)
fi
us_ids=""
if [ -f "$spec_dir/user-stories.md" ]; then
  us_ids=$(grep -E '^\*\*US-[0-9]+\*\*' "$spec_dir/user-stories.md" 2>/dev/null \
    | grep -Eo 'US-[0-9]+' | LC_ALL=C sort || true)
fi

fr_count=$(printf '%s\n' "$fr_ids" | grep -Ec '^FR-[0-9]+$' || true)
us_count=$(printf '%s\n' "$us_ids" | grep -Ec '^US-[0-9]+$' || true)
[ "$fr_count" -gt 0 ] || add_blocker "no_requirement_ids"
[ "$us_count" -gt 0 ] || add_blocker "no_user_story_ids"

duplicates=$(printf '%s\n%s\n' "$fr_ids" "$us_ids" | grep -E '^(FR|US)-[0-9]+$' | uniq -d || true)
if [ -n "$duplicates" ]; then
  while IFS= read -r id; do
    [ -n "$id" ] && add_blocker "duplicate_definition:$id"
  done <<EOF
$duplicates
EOF
fi

if [ -f "$spec_dir/user-stories.md" ]; then
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    grep -Eq "(^|[^A-Z0-9-])${id}([^0-9]|$)" "$spec_dir/user-stories.md" \
      || add_blocker "requirement_without_story:$id"
  done <<EOF
$fr_ids
EOF
fi

if [ "$feature_count" -gt 0 ]; then
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    covered=false
    for file in "$spec_dir"/acceptance/*.feature; do
      if grep -Eq "@${id}([^0-9]|$)" "$file"; then covered=true; break; fi
    done
    [ "$covered" = true ] || add_blocker "story_without_scenario:$id"
  done <<EOF
$us_ids
EOF
fi

if [ "$clone" = true ]; then
  [ -s "$spec_dir/deviations.md" ] || add_blocker "missing_or_empty:deviations.md"
  [ -s "$spec_dir/fit/registry.csv" ] || add_blocker "missing_or_empty:fit/registry.csv"
  set -- "$spec_dir"/fit/S*.md
  [ -f "$1" ] || add_blocker "missing:fit/S*.md"
fi

pass=true
[ "$blocker_count" -eq 0 ] || pass=false
result=$(printf '{"ok":true,"pass":%s,"clone":%s,"required_files":%s,"feature_files":%s,"fr_count":%s,"us_count":%s,"blocker_count":%s,"blockers":[%s]}' \
  "$pass" "$clone" "$required_count" "$feature_count" "$fr_count" "$us_count" "$blocker_count" "$blockers")

if [ -n "$out" ]; then
  mkdir -p "$(dirname "$out")" || {
    printf '%s\n' '{"ok":false,"error":"cannot create output directory"}'
    exit 0
  }
  tmp=$(mktemp "$(dirname "$out")/.eval-preflight.XXXXXX") || {
    printf '%s\n' '{"ok":false,"error":"mktemp failed"}'
    exit 0
  }
  printf '%s\n' "$result" > "$tmp"
  mv "$tmp" "$out" || {
    printf '%s\n' '{"ok":false,"error":"cannot publish preflight report"}'
    exit 0
  }
fi
printf '%s\n' "$result"
