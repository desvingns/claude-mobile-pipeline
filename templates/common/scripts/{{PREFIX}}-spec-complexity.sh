#!/usr/bin/env bash
# {{PREFIX}}-spec-complexity.sh — deterministic size gate for a SPEC, run BEFORE
# any implementation agent. Emits exactly one JSON line; it never edits anything.
#
# Usage: {{PREFIX}}-spec-complexity.sh --spec <file> [--cell-budget <N>]
#                                      [--freeze <path>]
#
# Why this exists. A SPEC whose acceptance surface is a cross-product — roles ×
# states × transports × error classes — cannot be converged by a review loop,
# because each semantic pass samples a different facet of the same design and
# returns findings that are all new. One such slice ran eight review cycles and
# produced STATE-001..008, SECURITY-001..004 and TESTS-001..011 without ever
# repeating an ID. The unit of work was an epic wearing a SPEC's front matter.
#
# The gate measures the DECLARED acceptance matrix, not the prose and not
# CHANGED_HINT. That is deliberate: on the run above, CHANGED_HINT named two
# modules while the implementation crossed seven plus a server grant, so every
# metric derived from it ranked the worst SPEC of the epic as one of the
# smallest. What the planner declares about roles/states/transports is the one
# statement of breadth that is both cheap to write and honest, because it is
# about behaviour rather than about files nobody has opened yet.
#
# `--freeze <path>` also writes the expanded cell list. That file is the frozen
# obligation matrix the semantic reviewer reports coverage against, so review
# terminates by construction instead of resampling a different facet per pass.
set -uo pipefail

emit() { printf '%s\n' "$1"; exit 0; }

json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"; s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"; s="${s//$'\r'/\\r}"; s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

spec=""
cell_budget=""
freeze=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --spec)        [ "$#" -ge 2 ] || emit '{"ok":false,"error":"--spec requires a file"}'; spec="$2"; shift 2 ;;
    --cell-budget) [ "$#" -ge 2 ] || emit '{"ok":false,"error":"--cell-budget requires a number"}'; cell_budget="$2"; shift 2 ;;
    --freeze)      [ "$#" -ge 2 ] || emit '{"ok":false,"error":"--freeze requires a path"}'; freeze="$2"; shift 2 ;;
    -h|--help) sed -n '2,28p' "$0"; exit 0 ;;
    *) emit "{\"ok\":false,\"error\":\"unknown arg: $(json_escape "$1")\"}" ;;
  esac
done

[ -n "$spec" ] || emit '{"ok":false,"error":"--spec is required"}'
[ -f "$spec" ] || emit "{\"ok\":false,\"error\":\"spec file not found: $(json_escape "$spec")\"}"

# Budget precedence: explicit arg > .claude/mp/config.json acceptanceCellBudget > 24.
if [ -z "$cell_budget" ]; then
  root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  cell_budget=$(grep -o '"acceptanceCellBudget"[[:space:]]*:[[:space:]]*[0-9]\{1,4\}' \
                "$root/.claude/mp/config.json" 2>/dev/null | grep -o '[0-9]\{1,4\}$' | head -n 1)
fi
case "${cell_budget:-}" in ''|*[!0-9]*) cell_budget=24 ;; esac

# ---- the declared acceptance matrix -------------------------------------
# Format (one line in the SPEC front matter):
#   Acceptance-matrix: role=owner,participant; state=active,grace,expired; transport=rpc,realtime
# Semicolons separate dimensions, commas separate that dimension's values.
matrix_line=$(grep -aiE '^[[:space:]]*Acceptance-matrix:' "$spec" 2>/dev/null | head -1 | sed -e 's/^[^:]*://')

dims=0
cells=1
dims_json=""
if [ -n "$(printf '%s' "$matrix_line" | tr -d '[:space:]')" ] &&
   [ "$(printf '%s' "$matrix_line" | tr -d '[:space:]')" != "—" ] &&
   [ "$(printf '%s' "$matrix_line" | tr -d '[:space:]')" != "-" ]; then
  old_ifs="$IFS"
  IFS=';'
  for dim in $matrix_line; do
    name="${dim%%=*}"
    values="${dim#*=}"
    name="$(printf '%s' "$name" | tr -d '[:space:]')"
    [ -n "$name" ] || continue
    [ "$dim" = "$name" ] && continue          # no '=' — not a dimension
    n=0
    IFS=','
    for v in $values; do
      [ -n "$(printf '%s' "$v" | tr -d '[:space:]')" ] && n=$((n + 1))
    done
    IFS=';'
    [ "$n" -gt 0 ] || continue
    dims=$((dims + 1))
    cells=$((cells * n))
    [ -n "$dims_json" ] && dims_json="$dims_json,"
    dims_json="$dims_json{\"name\":\"$(json_escape "$name")\",\"values\":$n}"
  done
  IFS="$old_ifs"
fi
[ "$dims" -gt 0 ] || cells=0

# ---- secondary, always-available breadth signals ------------------------
scenarios=$(grep -acE '^[[:space:]]*(Scenario|Scenario Outline|Сценарий|Структура сценария):' "$spec" 2>/dev/null || true)
case "$scenarios" in ''|*[!0-9]*) scenarios=0 ;; esac

layers=$(grep -aiE '^[[:space:]]*LAYERS:' "$spec" 2>/dev/null | head -1 |
         sed -e 's/^[^:]*://' -e 's/[,;]/ /g' |
         tr ' ' '\n' | grep -c '[a-zA-Z]' || true)
case "$layers" in ''|*[!0-9]*) layers=0 ;; esac

# A module is the prefix above `src/` or above the planner's `.../` ellipsis.
# Prose fragments ("SPEC 01/03", "values-ru/strings.xml") are rejected: a module
# path has no dot in any segment and no purely numeric segment.
modules=$(awk '
    /^[[:space:]]*CHANGED_HINT:/ { inblock=1; next }
    inblock && /^[[:space:]]*(TEST_TYPES|CONSTRAINTS|LAYERS|WHAT|TASK|PLATFORM|DESIGN_CAPSULE):/ { inblock=0 }
    inblock && /^===[[:space:]]*END SPEC/ { inblock=0 }
    inblock { print }
  ' "$spec" 2>/dev/null |
  grep -oE '[A-Za-z0-9_-]+(/[A-Za-z0-9_.-]+)+' |
  awk '
    {
      p=$0
      if (match(p, /\/(src|\.\.\.)\//)) p = substr(p, 1, RSTART-1)
      else { n=split(p, s, "/"); if (n<2 || s[n] !~ /\./) next; p = s[1]"/"s[2] }
      if (p ~ /\./ || p ~ /(^|\/)[0-9]+(\/|$)/ || p == "") next
      print p
    }' | LC_ALL=C sort -u | grep -c . || true)
case "$modules" in ''|*[!0-9]*) modules=0 ;; esac

# ---- verdict ------------------------------------------------------------
if [ "$dims" -eq 0 ]; then
  # Never guess a verdict from prose. An undeclared matrix is a missing input,
  # and saying so is more useful than a confident number derived from the one
  # field that was demonstrably wrong on the run this gate exists for.
  verdict=undeclared
  advice="no Acceptance-matrix declared — the planner must state role/state/transport/error dimensions before this SPEC is implemented"
elif [ "$cells" -ge "$cell_budget" ]; then
  verdict=split_recommended
  advice="$cells acceptance cells across $dims dimension(s) exceeds the budget of $cell_budget — split into independently shippable SPECs before implementing"
elif [ "$cells" -ge $(( cell_budget / 2 )) ]; then
  verdict=warn
  advice="$cells acceptance cells — near the budget; expect more than one semantic-review cycle"
else
  verdict=ok
  advice="$cells acceptance cells — within budget"
fi

# ---- freeze the obligation matrix ---------------------------------------
if [ -n "$freeze" ] && [ "$dims" -gt 0 ]; then
  freeze_dir=$(dirname "$freeze")
  mkdir -p "$freeze_dir" 2>/dev/null || true
  {
    printf '# Frozen acceptance matrix — %s\n\n' "$(basename "$spec")"
    printf 'Generated by {{PREFIX}}-spec-complexity.sh. %s cells across %s dimension(s).\n' "$cells" "$dims"
    printf 'Semantic review reports coverage against THIS list; it does not invent a new\n'
    printf 'decomposition per pass. A cell is covered when a test or an explicit\n'
    printf 'reviewer statement says what the behaviour is there.\n\n'
    printf '| # | cell | covered | evidence |\n|---|---|---|---|\n'
    printf '%s\n' "$matrix_line" | awk '
      {
        nd = split($0, d, ";")
        cnt = 0
        for (i = 1; i <= nd; i++) {
          if (index(d[i], "=") == 0) continue
          name = d[i]; sub(/=.*$/, "", name); gsub(/[ \t]/, "", name)
          vals = d[i]; sub(/^[^=]*=/, "", vals)
          nv = split(vals, v, ",")
          m = 0
          for (j = 1; j <= nv; j++) { gsub(/^[ \t]+|[ \t]+$/, "", v[j]); if (v[j] != "") { m++; keep[m] = v[j] } }
          if (m == 0) continue
          cnt++
          dim[cnt] = name
          dn[cnt] = m
          for (j = 1; j <= m; j++) dv[cnt, j] = keep[j]
        }
        if (cnt == 0) exit
        total = 1
        for (i = 1; i <= cnt; i++) total *= dn[i]
        for (k = 0; k < total; k++) {
          rem = k; line = ""
          for (i = cnt; i >= 1; i--) { idx[i] = rem % dn[i] + 1; rem = int(rem / dn[i]) }
          for (i = 1; i <= cnt; i++) line = line (i > 1 ? " · " : "") dim[i] "=" dv[i, idx[i]]
          printf "| %d | %s | ☐ | |\n", k + 1, line
        }
      }'
  } > "$freeze" 2>/dev/null || freeze=""
else
  freeze=""
fi

printf '{"ok":true,"verdict":"%s","cells":%s,"cell_budget":%s,"dimensions":[%s],"scenarios":%s,"modules":%s,"layers":%s,"matrix_declared":%s,"frozen_matrix":"%s","advice":"%s"}\n' \
  "$verdict" "$cells" "$cell_budget" "$dims_json" "$scenarios" "$modules" "$layers" \
  "$([ "$dims" -gt 0 ] && echo true || echo false)" "$(json_escape "$freeze")" "$(json_escape "$advice")"
