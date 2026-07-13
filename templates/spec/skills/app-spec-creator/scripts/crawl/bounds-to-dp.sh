#!/usr/bin/env bash
# bounds-to-dp.sh — augment element manifests (element-manifest.sh output) with EXACT dp metrics:
# per element adds "bounds_dp":"[x,y][x,y]" and "size_dp":"WxH" computed from the device density
# (dp = px * 160 / density). Turns "spacing: normal density" guesses into real numbers the
# fit checklists can quote ("FAB 56x56dp", "16dp gap").
#
# Usage: bounds-to-dp.sh --elements-dir <dir with ST*.json> --density <dpi>
# Rewrites each ST*.json in place (temp file + mv — never sed -i). ONE summary JSON line out.
set -u

emit() { printf '%s\n' "$1"; exit "${2:-0}"; }

elements_dir=""; density=""
while [ $# -gt 0 ]; do
  case "$1" in
    --elements-dir) elements_dir="${2-}"; shift 2 2>/dev/null || shift ;;
    --density)      density="${2-}";      shift 2 2>/dev/null || shift ;;
    -h|--help)      sed -n '2,9p' "$0"; exit 0 ;;
    *) emit "{\"ok\":false,\"error\":\"unknown arg: $1\"}" 2 ;;
  esac
done
[ -n "$elements_dir" ] && [ -d "$elements_dir" ] || emit '{"ok":false,"error":"--elements-dir missing or not a directory"}' 2
case "$density" in ''|*[!0-9]*) emit '{"ok":false,"error":"--density <dpi> is required (integer, e.g. 420)"}' 2 ;; esac
[ "$density" -gt 0 ] || emit '{"ok":false,"error":"--density must be > 0"}' 2

files=0
for f in "$elements_dir"/ST*.json; do
  [ -f "$f" ] || continue
  tmp="$(mktemp)"
  awk -v d="$density" '
    function dp(px) { return int((px * 160 / d) + 0.5) }
    {
      line = $0
      # element lines carry "bounds":"[x1,y1][x2,y2]" — augment them once
      if (line ~ /"bounds":"\[/ && line !~ /"bounds_dp"/ \
          && match(line, /"bounds":"\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]"/)) {
        b = substr(line, RSTART, RLENGTH)
        gsub(/"bounds":"|"/, "", b)              # [x1,y1][x2,y2]
        gsub(/\]\[/, ",", b); gsub(/\[|\]/, "", b)  # x1,y1,x2,y2
        split(b, c, ",")
        x1 = dp(c[1]); y1 = dp(c[2]); x2 = dp(c[3]); y2 = dp(c[4])
        add = "\"bounds_dp\":\"[" x1 "," y1 "][" x2 "," y2 "]\",\"size_dp\":\"" (x2 - x1) "x" (y2 - y1) "\""
        # insert right after the bounds attribute
        sub(/"bounds":"\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]"/, "&," add, line)
      }
      print line
    }
  ' "$f" > "$tmp" && mv "$tmp" "$f" || emit "{\"ok\":false,\"error\":\"failed to rewrite $f; partial evidence retained at $tmp\"}"
  files=$((files + 1))
done

[ "$files" -gt 0 ] || emit "{\"ok\":false,\"error\":\"no ST*.json manifests in $elements_dir\"}" 1
emit "{\"ok\":true,\"files\":$files,\"density\":$density}"
