#!/usr/bin/env bash
# {{PREFIX}}-retro.sh — L2 per-project retro: aggregate selfimprove/runs/*.jsonl into
# selfimprove/retro/retro-<YYYY-MM-DD>.md (per-agent pass-rate, user feedback, token/cost
# totals, recent failures). Deterministic awk only — no LLM. Emits ONE JSON line.
#
# Usage: {{PREFIX}}-retro.sh [--root <repo-root>] [--health] [--stale-days N]
set -u

emit() { printf '%s\n' "$1"; exit "${2:-0}"; }
esc() { printf '%s' "$1" | tr -d '\r\n' | sed 's/\\/\\\\/g; s/"/\\"/g'; }

root=""; health_only=false; stale_days="${TELEMETRY_STALE_DAYS:-7}"
while [ $# -gt 0 ]; do
  case "$1" in
    --root)    root="${2-}"; shift 2 2>/dev/null || shift ;;
    --health)  health_only=true; shift ;;
    --stale-days) stale_days="${2-}"; shift 2 2>/dev/null || shift ;;
    -h|--help) sed -n '2,8p' "$0"; exit 0 ;;
    *) emit "{\"ok\":false,\"error\":\"unknown arg: $(esc "$1")\"}" 2 ;;
  esac
done
[ -n "$root" ] || root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
case "$stale_days" in ''|*[!0-9]*) stale_days=7 ;; esac
runs_dir="$root/selfimprove/runs"
retro_dir="$root/selfimprove/retro"

events="$(cat "$runs_dir"/*.jsonl 2>/dev/null | grep -c '"agent"' || true)"
case "$events" in ''|*[!0-9]*) events=0 ;; esac

# Dormancy means the repository changed recently while no telemetry arrived in
# the same window. git --since and POSIX find -mtime need no GNU date parsing.
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
[ "$events" -gt 0 ] || emit "{\"ok\":false,\"error\":\"no run events in $(esc "$runs_dir") — record events first\",\"health\":\"$health\"}" 1

mkdir -p "$retro_dir" 2>/dev/null || emit "{\"ok\":false,\"error\":\"cannot create $(esc "$retro_dir")\"}"
date_tag="$(date -u +%Y-%m-%d)"
out="$retro_dir/retro-$date_tag.md"

{
  echo "# Retro — $date_tag"
  echo
  echo "Auto-aggregated from \`selfimprove/runs/*.jsonl\` ($events events). This is the"
  echo "**observe→reflect** step of the self-improvement loop. Turn findings into lessons"
  echo "(\`selfimprove/lessons.md\`) or plugin improvements (\`/{{PREFIX}} --improve\`); raw telemetry"
  echo "stays in runs/ — only this digest is meant to be read."
  echo
  echo "## Telemetry health"
  echo
  echo "Status: **$health** · recent events: $recent_events · recent commits: $recent_commits · window: $stale_days day(s)."
  if [ "$health" = dormant ]; then
    echo
    echo "> Telemetry is dormant while the repository is changing. Check record points before trusting cost/quality trends."
  fi
  echo
  echo "## Per-agent pass-rate"
  echo
  echo "| agent | runs | pass | fail | partial | pass-rate | eligible (>=3 runs) |"
  echo "|---|---|---|---|---|---|---|"
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
        r=runs[a];
        if (r >= 3) {
          pr=int((p[a]/r)*100);
          printf "| %s | %d | %d | %d | %d | %d%% | yes |\n", a, r, p[a]+0, f[a]+0, pt[a]+0, pr;
        } else {
          printf "| %s | %d | %d | %d | %d | n/a | no (<3 runs) |\n", a, r, p[a]+0, f[a]+0, pt[a]+0;
        }
      }
    }
  ' | sort
  echo
  echo "## User feedback (post-ship, agent=feedback)"
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
  if cat "$runs_dir"/*.jsonl 2>/dev/null | grep '"agent":"feedback"' | grep -E 'score=[123][^0-9]' >/dev/null 2>&1; then
    echo "Low-score events (latest 10):"
    echo
    cat "$runs_dir"/*.jsonl 2>/dev/null | grep '"agent":"feedback"' | grep -E 'score=[123][^0-9]' | tail -10 | sed 's/^/    /'
    echo
  fi
  echo "## Eval candidates from low feedback"
  echo
  if cat "$runs_dir"/*.jsonl 2>/dev/null | grep '"agent":"feedback"' | grep -E 'score=[123][^0-9]' >/dev/null 2>&1; then
    echo "Before changing a prompt, convert each candidate below into a reproducible eval case and record its expected outcome."
    echo
    cat "$runs_dir"/*.jsonl 2>/dev/null | grep '"agent":"feedback"' | grep -E 'score=[123][^0-9]' | tail -10 | sed 's/^/    /'
  else
    echo "_none_"
  fi
  echo
  echo "## Recorded usage, cost, duration, and correlation"
  echo
  cat "$runs_dir"/*.jsonl 2>/dev/null | awk '
    {
      events++;
      if ($0 !~ /"duration_ms":[0-9]+/) no_dur++;
      if ($0 !~ /"correlation_id":"[^"]+"/) no_corr++;
      usage = ($0 ~ /"(tokens_in|tokens_out|tokens_cached|tokens_reasoning|cost_usd|duration_ms)":/);
      if (usage) n++;
      if (match($0, /"usage_source":"provider"/)) provider++;
      else if (match($0, /"usage_source":"estimated"/)) estimated++;
      else if (usage) unspecified++;
      if (match($0, /"tokens_in":[0-9]+/))  ti += substr($0, RSTART+12, RLENGTH-12)+0;
      if (match($0, /"tokens_out":[0-9]+/)) { to += substr($0, RSTART+13, RLENGTH-13)+0 }
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
      # Instrumentation compliance is reported before any conclusion drawn from the
      # numbers above. Both fields are required per contract-telemetry.md, and a run
      # whose events lack them cannot tell you where its time went — every cost claim
      # about it is inference from step boundaries, not measurement.
      if (events>0) {
        printf "Instrumentation: %d events · missing duration_ms: %d (%.0f%%) · missing correlation_id: %d (%.0f%%)\n", \
               events, no_dur, 100*no_dur/events, no_corr, 100*no_corr/events;
        if (no_dur*2 > events) print "**Under-instrumented**: over half the events carry no duration. Fix recording before drawing cost conclusions from this window.";
      }
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
  echo "## Failure/partial clusters"
  echo
  if cat "$runs_dir"/*.jsonl 2>/dev/null | grep -E '"verdict":"(fail|partial)"' >/dev/null 2>&1; then
    cat "$runs_dir"/*.jsonl 2>/dev/null | awk '
      /"verdict":"(fail|partial)"/ {
        a=""; v=""; metric=""; note="";
        if (match($0, /"agent":"[^"]*"/)) a=substr($0, RSTART+9, RLENGTH-10);
        if (match($0, /"verdict":"[^"]*"/)) v=substr($0, RSTART+11, RLENGTH-12);
        if (match($0, /"metric":"[^"]*"/)) metric=substr($0, RSTART+10, RLENGTH-11);
        if (match($0, /"note":"[^"]*"/)) note=substr($0, RSTART+8, RLENGTH-9);
        key=a " | " v " | " metric " | " note;
        count[key]++;
        evidence[key]=$0;
      }
      END {
        for (key in count) printf "%d\t%s\n  evidence: %s\n", count[key], key, evidence[key];
      }
    ' | sort -rn -k1,1
  else
    echo "_none_"
  fi
  echo
} > "$out"

emit "{\"ok\":true,\"retro\":\"$(esc "$out")\",\"events\":$events}"
