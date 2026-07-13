#!/usr/bin/env bash
# {{PREFIX}}-pixel-diff.sh — objective screenshot comparison for the --fit gate (ImageMagick).
# Computes a normalized RMSE between the reference and the built capture and writes a diff
# heatmap. The multimodal fit agent keeps semantic judgment; this gives it (and the report) a
# deterministic number that cannot be charmed.
#
# Usage: {{PREFIX}}-pixel-diff.sh --reference <png> --built <png> [--out <heatmap.png>]
# Output: ONE JSON line {"ok":true,"similarity":87.7,"rmse_pct":12.3,"heatmap":"...","resized":false}
# Graceful degrade: ImageMagick absent -> {"ok":false,"error":"tool_missing: ..."} exit 0.
set -u

emit() { printf '%s\n' "$1"; exit 0; }
esc() { printf '%s' "$1" | tr -d '\r\n' | sed 's/\\/\\\\/g; s/"/\\"/g'; }

reference=""; built=""; out=""
while [ $# -gt 0 ]; do
  case "$1" in
    --reference) reference="${2-}"; shift 2 2>/dev/null || shift ;;
    --built)     built="${2-}";     shift 2 2>/dev/null || shift ;;
    --out)       out="${2-}";       shift 2 2>/dev/null || shift ;;
    -h|--help)   sed -n '2,10p' "$0"; exit 0 ;;
    *) emit "{\"ok\":false,\"error\":\"unknown arg: $(esc "$1")\"}" ;;
  esac
done
[ -n "$reference" ] && [ -f "$reference" ] || emit '{"ok":false,"error":"--reference missing or not a file"}'
[ -n "$built" ] && [ -f "$built" ]         || emit '{"ok":false,"error":"--built missing or not a file"}'
[ -n "$out" ] || out="${built%.png}-diff.png"

# Resolve ImageMagick: IM7 (`magick`) preferred, IM6 (`compare`/`identify`) fallback.
MAGICK=""; COMPARE=""; IDENTIFY=""
if command -v magick >/dev/null 2>&1; then
  MAGICK="magick"; COMPARE="magick compare"; IDENTIFY="magick identify"
elif command -v compare >/dev/null 2>&1 && command -v identify >/dev/null 2>&1; then
  COMPARE="compare"; IDENTIFY="identify"
else
  emit '{"ok":false,"error":"tool_missing: ImageMagick not found (need `magick` or `compare`+`identify`). Install: https://imagemagick.org"}'
fi

dims() { $IDENTIFY -format '%wx%h' "$1" 2>/dev/null | head -1; }
ref_dims="$(dims "$reference")"; built_dims="$(dims "$built")"
[ -n "$ref_dims" ] || emit "{\"ok\":false,\"error\":\"cannot identify $(esc "$reference")\"}"
[ -n "$built_dims" ] || emit "{\"ok\":false,\"error\":\"cannot identify $(esc "$built")\"}"

# Normalize: compare needs equal canvases. Resize a mismatched BUILT capture to the reference
# dims (forced) into a temp file — the originals are never modified.
cmp_built="$built"; resized=false; tmp=""
if [ "$ref_dims" != "$built_dims" ]; then
  evidence_root="${MP_PIXEL_DIFF_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/mobile-pipeline/pixel-diff}"
  mkdir -p "$evidence_root" 2>/dev/null || emit '{"ok":false,"error":"cannot create pixel-diff evidence archive"}'
  tmp="$evidence_root/$(date -u +%Y%m%dT%H%M%SZ)-$$-resized.png"; suffix=0
  while [ -e "$tmp" ]; do
    suffix=$((suffix + 1))
    tmp="$evidence_root/$(date -u +%Y%m%dT%H%M%SZ)-$$-$suffix-resized.png"
  done
  if [ -n "$MAGICK" ]; then
    $MAGICK "$built" -resize "${ref_dims}!" "$tmp" 2>/dev/null \
      || emit "{\"ok\":false,\"error\":\"resize failed; partial evidence retained at $(esc "$tmp")\"}"
  else
    convert "$built" -resize "${ref_dims}!" "$tmp" 2>/dev/null \
      || emit "{\"ok\":false,\"error\":\"resize failed; partial evidence retained at $(esc "$tmp")\"}"
  fi
  [ -f "$tmp" ] || emit '{"ok":false,"error":"resize produced no evidence file"}'
  cmp_built="$tmp"; resized=true
fi

mkdir -p "$(dirname "$out")" 2>/dev/null || true
# RMSE metric: stderr like "12345.6 (0.18837)" — the parenthesised value is normalized 0..1.
metric="$($COMPARE -metric RMSE "$reference" "$cmp_built" "$out" 2>&1 >/dev/null | tr -d '\n')"

frac="$(printf '%s' "$metric" | sed -n 's/.*(\([0-9.eE+-]*\)).*/\1/p')"
case "$frac" in ''|*[!0-9.eE+-]*) emit "{\"ok\":false,\"error\":\"unparseable compare output: $(esc "$metric")\"}" ;; esac

read -r rmse_pct similarity <<EOF2
$(awk -v f="$frac" 'BEGIN { p = f * 100; if (p < 0) p = 0; if (p > 100) p = 100; printf "%.1f %.1f", p, 100 - p }')
EOF2

emit "{\"ok\":true,\"similarity\":$similarity,\"rmse_pct\":$rmse_pct,\"heatmap\":\"$(esc "$out")\",\"reference_dims\":\"$ref_dims\",\"built_dims\":\"$built_dims\",\"resized\":$resized,\"resized_evidence\":\"$(esc "$tmp")\"}"
