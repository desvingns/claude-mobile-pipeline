#!/usr/bin/env bash
# selfimprove/retro.sh — deterministic L2 retro and dormant-telemetry health check.
# Usage: selfimprove/retro.sh [--health] [--stale-days N]
set -u

emit() { printf '%s\n' "$1"; exit "${2:-0}"; }
esc() { printf '%s' "$1" | tr -d '\r\n' | sed 's/\\/\\\\/g; s/"/\\"/g'; }

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
runs_dir="$here/runs"
retro_dir="$here/retro"
health_only=false
stale_days="${TELEMETRY_STALE_DAYS:-7}"
while [ $# -gt 0 ]; do
  case "$1" in
    --health) health_only=true; shift ;;
    --stale-days) stale_days="${2-}"; shift 2 2>/dev/null || shift ;;
    -h|--help) sed -n '2,3p' "$0"; exit 0 ;;
    *) emit "{\"ok\":false,\"error\":\"unknown arg: $(esc "$1")\"}" 2 ;;
  esac
done
case "$stale_days" in ''|*[!0-9]*) stale_days=7 ;; esac

events="$(cat "$runs_dir"/*.jsonl 2>/dev/null | grep -c '"agent"' || true)"
case "$events" in ''|*[!0-9]*) events=0 ;; esac
recent_commits="$(git -C "$root" log --since="$stale_days days ago" --format=%H 2>/dev/null | awk 'END { print NR+0 }')"
case "$recent_commits" in ''|*[!0-9]*) recent_commits=0 ;; esac
recent_events=false
if [ -d "$runs_dir" ] && find "$runs_dir" -type f -name '*.jsonl' -mtime "-$stale_days" -print 2>/dev/null | grep -q .; then
  recent_events=true
fi
health=idle
[ "$recent_events" = true ] && health=active
[ "$recent_events" = false ] && [ "$recent_commits" -gt 0 ] && health=dormant
if [ "$health_only" = true ]; then
  emit "{\"ok\":true,\"health\":\"$health\",\"events\":$events,\"recent_events\":$recent_events,\"recent_commits\":$recent_commits,\"stale_days\":$stale_days}"
fi
[ "$events" -gt 0 ] || emit "{\"ok\":false,\"error\":\"no run events\",\"health\":\"$health\"}" 1

mkdir -p "$retro_dir" || emit '{"ok":false,"error":"cannot create retro directory"}' 1
date_tag="$(date -u +%Y-%m-%d)"
out="$retro_dir/retro-$date_tag.md"

{
  echo "# Retro — $date_tag"
  echo
  echo "Auto-aggregated from \`selfimprove/runs/*.jsonl\` ($events events). Raw events remain"
  echo "gitignored; promote only evidence-backed lessons or eval cases."
  echo
  echo "## Telemetry health"
  echo
  echo "Status: **$health** · recent events: $recent_events · recent commits: $recent_commits · window: $stale_days day(s)."
  if [ "$health" = dormant ]; then
    echo
    echo "> Telemetry is dormant while the repository is changing. Repair record points before trusting trends."
  fi
  echo
  echo "## Per-agent pass-rate"
  echo
  echo "| agent | runs | pass | fail | partial | pass-rate |"
  echo "|---|---|---|---|---|---|"
  cat "$runs_dir"/*.jsonl 2>/dev/null | awk '
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
  echo "## User feedback"
  echo
  cat "$runs_dir"/*.jsonl 2>/dev/null | awk '
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
  echo "## Recorded usage, cost, duration, and correlation"
  echo
  cat "$runs_dir"/*.jsonl 2>/dev/null | awk '
    {
      usage = ($0 ~ /"(tokens_in|tokens_out|tokens_cached|tokens_reasoning|cost_usd|duration_ms)":/);
      if (usage) n++;
      if (match($0, /"usage_source":"provider"/)) provider++;
      else if (match($0, /"usage_source":"estimated"/)) estimated++;
      else if (usage) unspecified++;
      if (match($0, /"tokens_in":[0-9]+/)) ti += substr($0, RSTART+12, RLENGTH-12)+0;
      if (match($0, /"tokens_out":[0-9]+/)) to += substr($0, RSTART+13, RLENGTH-13)+0;
      if (match($0, /"tokens_cached":[0-9]+/)) tc += substr($0, RSTART+16, RLENGTH-16)+0;
      if (match($0, /"tokens_reasoning":[0-9]+/)) tr += substr($0, RSTART+19, RLENGTH-19)+0;
      if (match($0, /"cost_usd":[0-9.]+/)) cost += substr($0, RSTART+11, RLENGTH-11)+0;
      if (match($0, /"duration_ms":[0-9]+/)) { dur += substr($0, RSTART+14, RLENGTH-14)+0; dn++ }
      if (match($0, /"correlation_id":"[^"]+"/)) corr++;
    }
    END {
      if (n>0) printf "Usage events: %d · input: %d · output: %d · cached input: %d · reasoning output: %d\n", n, ti, to, tc, tr;
      else print "_no token usage recorded_";
      printf "Cost (structured): $%.6f · duration: %d ms total", cost, dur;
      if (dn>0) printf " / %.0f ms avg", dur/dn;
      printf " · correlated events: %d\n", corr;
      printf "Usage source: provider %d · estimated %d · unspecified %d\n", provider, estimated, unspecified;
    }
  '
  echo
  echo "## Recent fail/partial events (latest 20)"
  echo
  if cat "$runs_dir"/*.jsonl 2>/dev/null | grep -E '"verdict":"(fail|partial)"' >/dev/null 2>&1; then
    cat "$runs_dir"/*.jsonl 2>/dev/null | grep -E '"verdict":"(fail|partial)"' | tail -20 | sed 's/^/    /'
  else
    echo "_none_"
  fi
  echo
  echo "## Proposed improvements (human-gated)"
  echo
  echo "- [ ] Inspect the lowest measured pass-rate only when its sample has at least 3 runs."
  echo "- [ ] Cluster concrete fail/partial evidence; never copy this checklist into lessons.md."
  echo "- [ ] Promote low-feedback evidence into an eval candidate before changing a prompt."
  echo
} > "$out"

emit "{\"ok\":true,\"retro\":\"$(esc "$out")\",\"events\":$events,\"health\":\"$health\"}"
