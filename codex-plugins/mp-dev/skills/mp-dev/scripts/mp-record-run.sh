#!/usr/bin/env bash
# mp-record-run.sh — L1 telemetry capture for the /mp pipeline.
# Appends ONE structured event (a single JSON line) to <repo>/selfimprove/runs/<YYYY-MM>.jsonl
# and reports whether a per-project retro is due. Fire-and-forget by contract: ALWAYS exits 0
# with exactly one JSON line on stdout — telemetry must never block or fail the pipeline.
#
# Usage:
#   mp-record-run.sh --agent <step> --verdict pass|fail|partial \
#     [--model M] [--metric "tests=42/0;cov=67%"] [--retry N] [--note "..."] \
#     [--tokens-in N] [--tokens-out N] [--tokens-cached N] [--tokens-reasoning N] \
#     [--cost "legacy estimate"] [--cost-usd N.N] [--duration-ms N] \
#     [--usage-source provider|estimated] [--correlation-id ID] [--root <repo-root>]
#
# Output: {"ok":true,"log":"...","events_total":N,"events_since_retro":N,"retro_due":false}
# retro_due fires when >= $REFLECT_AFTER (default 10) events were recorded after the newest
# selfimprove/retro/retro-YYYY-MM-DD.md (events from the retro's own day do not count).
set -u

emit() { printf '%s\n' "$1"; exit 0; }
esc() { printf '%s' "$1" | tr -d '\r\n' | sed 's/\\/\\\\/g; s/"/\\"/g'; }

agent=""; model=""; verdict=""; metric=""; retry="0"; note=""
tokens_in=""; tokens_out=""; tokens_cached=""; tokens_reasoning=""
cost=""; cost_usd=""; duration_ms=""; usage_source=""; correlation_id=""; root=""
while [ $# -gt 0 ]; do
  key="$1"; val="${2-}"
  case "$key" in
    --agent)      agent="$val" ;;
    --model)      model="$val" ;;
    --verdict)    verdict="$val" ;;
    --metric)     metric="$val" ;;
    --retry)      retry="$val" ;;
    --note)       note="$val" ;;
    --tokens-in)  tokens_in="$val" ;;
    --tokens-out) tokens_out="$val" ;;
    --tokens-cached|--cached-tokens) tokens_cached="$val" ;;
    --tokens-reasoning|--reasoning-tokens) tokens_reasoning="$val" ;;
    --cost)       cost="$val" ;;
    --cost-usd)   cost_usd="$val" ;;
    --duration-ms) duration_ms="$val" ;;
    --usage-source) usage_source="$val" ;;
    --correlation-id|--run-id) correlation_id="$val" ;;
    --root)       root="$val" ;;
    -h|--help)    sed -n '2,15p' "$0"; exit 0 ;;
    *) emit "{\"ok\":false,\"error\":\"unknown arg: $(esc "$key")\"}" ;;
  esac
  shift 2 2>/dev/null || shift
done

[ -n "$agent" ]   || emit '{"ok":false,"error":"--agent is required"}'
[ -n "$verdict" ] || emit '{"ok":false,"error":"--verdict is required"}'
case "$verdict" in pass|fail|partial) ;; *) emit '{"ok":false,"error":"--verdict must be pass, fail, or partial"}' ;; esac
case "$retry" in ''|*[!0-9]*) retry=0 ;; esac
case "$tokens_in"  in *[!0-9]*) tokens_in=""  ;; esac
case "$tokens_out" in *[!0-9]*) tokens_out="" ;; esac
case "$tokens_cached"   in *[!0-9]*) tokens_cached=""   ;; esac
case "$tokens_reasoning" in *[!0-9]*) tokens_reasoning="" ;; esac
case "$duration_ms" in *[!0-9]*) duration_ms="" ;; esac
if [ -n "$cost_usd" ] && \
   ! printf '%s\n' "$cost_usd" | grep -Eq '^(0|[1-9][0-9]*)(\.[0-9]+)?$'; then
  emit '{"ok":false,"error":"--cost-usd must be a non-negative JSON decimal (for example 0.0125)"}'
fi
case "$usage_source" in ''|provider|estimated) ;; *) emit '{"ok":false,"error":"--usage-source must be provider or estimated"}' ;; esac
if [ -z "$usage_source" ] && \
   [ -n "$tokens_in$tokens_out$tokens_cached$tokens_reasoning$cost$cost_usd$duration_ms" ]; then
  # Backward compatibility: the original token/cost contract explicitly used
  # rough estimates, so an unmarked legacy usage payload is estimated.
  usage_source=estimated
fi

if [ -z "$root" ]; then
  root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi
project="$(basename "$root")"
runs_dir="$root/selfimprove/runs"
mkdir -p "$runs_dir" 2>/dev/null || emit "{\"ok\":false,\"error\":\"cannot create $(esc "$runs_dir")\"}"

ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
log="$runs_dir/$(date -u +%Y-%m).jsonl"

line="{\"ts\":\"$(esc "$ts")\",\"project\":\"$(esc "$project")\",\"agent\":\"$(esc "$agent")\""
line="$line,\"model\":\"$(esc "$model")\",\"verdict\":\"$(esc "$verdict")\",\"metric\":\"$(esc "$metric")\""
line="$line,\"retry\":$retry,\"note\":\"$(esc "$note")\""
[ -n "$tokens_in" ]  && line="$line,\"tokens_in\":$tokens_in"
[ -n "$tokens_out" ] && line="$line,\"tokens_out\":$tokens_out"
[ -n "$tokens_cached" ] && line="$line,\"tokens_cached\":$tokens_cached"
[ -n "$tokens_reasoning" ] && line="$line,\"tokens_reasoning\":$tokens_reasoning"
[ -n "$cost" ]       && line="$line,\"cost\":\"$(esc "$cost")\""
[ -n "$cost_usd" ]   && line="$line,\"cost_usd\":$cost_usd"
[ -n "$duration_ms" ] && line="$line,\"duration_ms\":$duration_ms"
[ -n "$usage_source" ] && line="$line,\"usage_source\":\"$usage_source\""
[ -n "$correlation_id" ] && line="$line,\"correlation_id\":\"$(esc "$correlation_id")\""
line="$line}"
printf '%s\n' "$line" >> "$log" 2>/dev/null || emit "{\"ok\":false,\"error\":\"cannot append to $(esc "$log")\"}"

# --- retro-due bookkeeping (lexicographic ISO-8601 compare; no GNU date needed) -----------------
cutoff=""
retro_dir="$root/selfimprove/retro"
if [ -d "$retro_dir" ]; then
  newest="$(ls "$retro_dir"/retro-????-??-??.md 2>/dev/null | sort | tail -1 || true)"
  if [ -n "$newest" ]; then
    d="$(basename "$newest" .md)"; d="${d#retro-}"
    cutoff="${d}T23:59:59Z"
  fi
fi
counts="$(cat "$runs_dir"/*.jsonl 2>/dev/null | awk -v c="$cutoff" '
  /"ts":"/ {
    total++
    if (match($0, /"ts":"[^"]*"/)) { t = substr($0, RSTART+6, RLENGTH-7); if (c == "" || t > c) since++ }
  }
  END { printf "%d %d", total+0, since+0 }')"
total="${counts%% *}"; since="${counts##* }"
case "$total" in ''|*[!0-9]*) total=0 ;; esac
case "$since" in ''|*[!0-9]*) since=0 ;; esac

threshold="${REFLECT_AFTER:-10}"
case "$threshold" in ''|*[!0-9]*) threshold=10 ;; esac
due=false
[ "$since" -ge "$threshold" ] && due=true

emit "{\"ok\":true,\"log\":\"$(esc "$log")\",\"events_total\":$total,\"events_since_retro\":$since,\"retro_due\":$due}"
