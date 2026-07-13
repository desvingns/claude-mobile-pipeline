#!/usr/bin/env bash
# selfimprove/reflect.sh — L2 Reflect
# Aggregate selfimprove/runs/*.jsonl into a retro report. Pure awk, no LLM.
# Output: selfimprove/retro/retro-<YYYY-MM-DD>.md
legacy_here="$(cd "$(dirname "$0")" && pwd)"
exec bash "$legacy_here/retro.sh" "$@"

set -eu

here="$(cd "$(dirname "$0")" && pwd)"
runs_dir="$here/runs"
retro_dir="$here/retro"
mkdir -p "$retro_dir"
date_tag="$(date -u +%Y-%m-%d)"
out="$retro_dir/retro-$date_tag.md"

shopt -s nullglob
logs=("$runs_dir"/*.jsonl)
if [ ${#logs[@]} -eq 0 ]; then
  echo "reflect: no run logs in $runs_dir — record events first (./record-run.sh ...)." >&2
  exit 1
fi

total="$(cat "${logs[@]}" | grep -c '"agent"' || true)"

{
  echo "# Retro — $date_tag"
  echo
  echo "Auto-aggregated from \`selfimprove/runs/*.jsonl\` ($total events). This is the"
  echo "**observe→reflect** step of the loop; turn the findings into proposals via"
  echo "\`selfimprove/REFLECTION-PROMPT.md\`, then route them through a human gate to the"
  echo "change-log / a PR. Raw telemetry stays in runs/ (gitignored); only this digest is tracked."
  echo
  echo "## Per-agent pass-rate"
  echo
  echo "| agent | runs | pass | fail | partial | pass-rate |"
  echo "|---|---|---|---|---|---|"
  cat "${logs[@]}" | awk '
    {
      a=""; v="";
      if (match($0, /"agent":"[^"]*"/))   a=substr($0, RSTART+9,  RLENGTH-10);
      if (match($0, /"verdict":"[^"]*"/)) v=substr($0, RSTART+11, RLENGTH-12);
      if (a=="") next;
      runs[a]++;
      if (v=="pass") p[a]++; else if (v=="fail") f[a]++; else if (v=="partial") pt[a]++;
    }
    END {
      for (a in runs) {
        r=runs[a]; pr=(r>0)?int((p[a]/r)*100):0;
        printf "| %s | %d | %d | %d | %d | %d%% |\n", a, r, p[a]+0, f[a]+0, pt[a]+0, pr;
      }
    }
  ' | sort
  echo
  echo "## User feedback (post-ship, agent=feedback)"
  echo
  cat "${logs[@]}" | awk '
    /"agent":"feedback"/ {
      n++;
      if (match($0, /score=[0-9]+/)) { s=substr($0, RSTART+6, RLENGTH-6)+0; sum+=s; if (s<=3) low++ }
    }
    END {
      if (n>0) printf "Events: %d · avg score: %.1f · low (<=3): %d\n", n, sum/n, low+0;
      else print "_none recorded yet_";
    }
  '
  echo
  echo "## Recorded token/cost estimates"
  echo
  cat "${logs[@]}" | awk '
    {
      if (match($0, /"tokens_in":[0-9]+/))  { ti += substr($0, RSTART+12, RLENGTH-12)+0; n++ }
      if (match($0, /"tokens_out":[0-9]+/)) { to += substr($0, RSTART+13, RLENGTH-13)+0 }
    }
    END {
      if (n>0) printf "Events with estimates: %d · tokens_in total: %d · tokens_out total: %d\n", n, ti, to;
      else print "_no token estimates recorded_";
    }
  '
  echo
  echo "## Recent fail/partial events (latest 20)"
  echo
  if grep -hE '"verdict":"(fail|partial)"' "${logs[@]}" >/dev/null 2>&1; then
    grep -hE '"verdict":"(fail|partial)"' "${logs[@]}" | tail -20 | sed 's/^/    /'
  else
    echo "_none_"
  fi
  echo
  echo "## Proposed improvements (fill in via REFLECTION-PROMPT.md, human-gated)"
  echo
  echo "- [ ] weakest agent by pass-rate → inspect its prompt/template, propose one minimal edit"
  echo "- [ ] top recurring failure cluster → add a guard + a durable line to lessons.md"
  echo "- [ ] any flaky signal (same input, different verdict) → quarantine / stabilize"
  echo
} > "$out"

echo "wrote $out"
