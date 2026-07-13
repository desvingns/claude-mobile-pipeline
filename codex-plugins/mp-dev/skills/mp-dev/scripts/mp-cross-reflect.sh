#!/usr/bin/env bash
# mp-cross-reflect.sh — aggregate self-improvement signals across ALL mobile-pipeline
# projects into one digest, flagging themes that recur in >=2 projects as plugin-improvement
# candidates. The mp-reflect agent reads the digest and stages queued proposals.
# Cross-platform bash; emits one JSON line. Pure collection + keyword grouping (no LLM here).
#
# Usage: mp-cross-reflect.sh [<mp_repo>]
#   Projects come from $MP_PROJECTS or ~/.config/mobile-pipeline/projects.txt (one repo root per line;
#   use Git-Bash paths like /d/diet_helper). Reads each project's selfimprove/lessons.md + retro/*.md.
set -uo pipefail
MP="${1:-$(pwd)}"
LIST="${MP_PROJECTS:-$HOME/.config/mobile-pipeline/projects.txt}"
emit() { printf '%s\n' "$1"; exit 0; }
[ -f "$LIST" ] || emit "{\"ok\":false,\"error\":\"no projects list at $LIST (one project root per line)\"}"

OUT="$MP/.ai/reflections"; mkdir -p "$OUT"
cache_root="${MP_REFLECT_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/mobile-pipeline/cross-reflect}"
base_stamp="$(date -u +%Y%m%d-%H%M%S)-$$"; STAMP="$base_stamp"; suffix=0
DIGEST="$OUT/$STAMP-digest.md"; run_dir="$cache_root/$STAMP"
while [ -e "$DIGEST" ] || [ -e "$run_dir" ]; do
  suffix=$((suffix + 1)); STAMP="$base_stamp-$suffix"
  DIGEST="$OUT/$STAMP-digest.md"; run_dir="$cache_root/$STAMP"
done
NPROJ=$(grep -cvE '^[[:space:]]*(#|$)' "$LIST" 2>/dev/null || true)
mkdir -p "$run_dir" || emit "{\"ok\":false,\"error\":\"cannot preserve reflection evidence at $run_dir\"}"
tmp="$run_dir/raw.tsv"

# collect: "<project>\t<lesson>" per bullet line from each project's self-improve sources
while IFS= read -r proj; do
  case "$proj" in ''|\#*) continue ;; esac
  [ -d "$proj" ] || continue
  name="$(basename "$proj")"
  for src in "$proj/selfimprove/lessons.md" "$proj"/selfimprove/retro/*.md "$proj/.ai/lessons.md"; do
    [ -f "$src" ] || continue
    grep -E '^[[:space:]]*[-*][[:space:]]' "$src" 2>/dev/null \
      | sed -E 's/^[[:space:]]*[-*][[:space:]]+//' \
      | while IFS= read -r line; do printf '%s\t%s\n' "$name" "$line"; done >> "$tmp"
  done
done < "$LIST"

set -C
{
  echo "# Cross-project reflection digest — $STAMP"
  echo
  echo "Projects scanned: $NPROJ (from \`$LIST\`). Collected lesson lines: $(wc -l < "$tmp" | tr -d ' ')."
  echo
  echo "## Recurring themes (significant keyword seen in >=2 projects)"
  echo "Heuristic grouping — the mp-reflect agent decides which are real plugin improvements."
  echo
} > "$DIGEST" || emit "{\"ok\":false,\"error\":\"refusing to overwrite reflection digest at $DIGEST\"}"
set +C

# keyword -> distinct project count (+ example lines); flag >=2 projects
awk -F'\t' '
  { proj=$1; raw=$2; line=tolower($2); gsub(/[^a-z0-9 ]/," ",line); nn=split(line,w," ");
    delete seen;
    for(i=1;i<=nn;i++){ k=w[i];
      if(length(k)>4 && !(k in seen)){ seen[k]=1;
        if(!((k SUBSEP proj) in pp)){ pp[k SUBSEP proj]=1; cnt[k]++ }
        if(length(ex[k])<240) ex[k]=ex[k] (ex[k]?" | ":"") proj ": " substr(raw,1,70)
      } } }
  END{ for(k in cnt) if(cnt[k]>=2) printf "- **%s** — %d projects: %s\n", k, cnt[k], ex[k] }
' "$tmp" | sort >> "$DIGEST"

{
  echo
  echo "## All collected lessons (raw, by project)"
} >> "$DIGEST"
sed -E 's/\t/ — /; s/^/- /' "$tmp" | sort >> "$DIGEST"

themes=$(grep -cE '^- \*\*' "$DIGEST" 2>/dev/null || true)
emit "{\"ok\":true,\"digest\":\"${DIGEST#"$MP"/}\",\"evidence\":\"$tmp\",\"projects\":$NPROJ,\"recurring_themes\":$themes}"
