#!/usr/bin/env bash
# selfimprove/record-run.sh — L1 Capture
# Append one structured run event (a single JSON line) to selfimprove/runs/<YYYY-MM>.jsonl.
# No deps beyond coreutils. Wire this into your runner/reviewer/CI so events accrue automatically.
#
# Usage:
#   ./record-run.sh --agent <name> --verdict pass|fail|partial \
#       [--model M] [--metric "tests=42/0;cov=67%"] [--retry N] [--note "..."] [--project P] \
#       [--tokens-in N] [--tokens-out N] [--tokens-cached N] [--tokens-reasoning N] \
#       [--cost "legacy estimate"] [--cost-usd N.N] [--duration-ms N] \
#       [--usage-source provider|estimated] [--correlation-id ID]
set -u

here="$(cd "$(dirname "$0")" && pwd)"
runs_dir="$here/runs"
mkdir -p "$runs_dir"

agent=""; model=""; verdict=""; metric=""; retry="0"; note=""
tokens_in=""; tokens_out=""; tokens_cached=""; tokens_reasoning=""
cost=""; cost_usd=""; duration_ms=""; usage_source=""; correlation_id=""
project="$(basename "$(cd "$here/.." && pwd)")"

while [ $# -gt 0 ]; do
  key="$1"; val="${2-}"
  case "$key" in
    --agent)      agent="$val" ;;
    --model)      model="$val" ;;
    --verdict)    verdict="$val" ;;
    --metric)     metric="$val" ;;
    --retry)      retry="$val" ;;
    --note)       note="$val" ;;
    --project)    project="$val" ;;
    --tokens-in)  tokens_in="$val" ;;
    --tokens-out) tokens_out="$val" ;;
    --tokens-cached|--cached-tokens) tokens_cached="$val" ;;
    --tokens-reasoning|--reasoning-tokens) tokens_reasoning="$val" ;;
    --cost)       cost="$val" ;;
    --cost-usd)   cost_usd="$val" ;;
    --duration-ms) duration_ms="$val" ;;
    --usage-source) usage_source="$val" ;;
    --correlation-id|--run-id) correlation_id="$val" ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "record-run: unknown arg: $key" >&2; exit 2 ;;
  esac
  shift 2 2>/dev/null || shift
done

[ -n "$agent" ]   || { echo "record-run: --agent is required" >&2; exit 2; }
[ -n "$verdict" ] || { echo "record-run: --verdict is required" >&2; exit 2; }
case "$verdict" in pass|fail|partial) ;; *) echo "record-run: invalid --verdict" >&2; exit 2 ;; esac
case "$retry" in ''|*[!0-9]*) retry=0 ;; esac
case "$tokens_in"  in *[!0-9]*) tokens_in=""  ;; esac
case "$tokens_out" in *[!0-9]*) tokens_out="" ;; esac
case "$tokens_cached"   in *[!0-9]*) tokens_cached=""   ;; esac
case "$tokens_reasoning" in *[!0-9]*) tokens_reasoning="" ;; esac
case "$duration_ms" in *[!0-9]*) duration_ms="" ;; esac
if [ -n "$cost_usd" ] && \
   ! printf '%s\n' "$cost_usd" | grep -Eq '^(0|[1-9][0-9]*)(\.[0-9]+)?$'; then
  echo "record-run: --cost-usd must be a non-negative JSON decimal (for example 0.0125)" >&2
  exit 2
fi
case "$usage_source" in ''|provider|estimated) ;; *) echo "record-run: invalid --usage-source" >&2; exit 2 ;; esac
if [ -z "$usage_source" ] && \
   [ -n "$tokens_in$tokens_out$tokens_cached$tokens_reasoning$cost$cost_usd$duration_ms" ]; then
  usage_source=estimated
fi

ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
log="$runs_dir/$(date -u +%Y-%m).jsonl"

# minimal JSON-string escaping: backslash, double-quote, strip CR/LF
esc() { printf '%s' "$1" | tr -d '\r\n' | sed 's/\\/\\\\/g; s/"/\\"/g'; }

line="$(printf '{"ts":"%s","project":"%s","agent":"%s","model":"%s","verdict":"%s","metric":"%s","retry":%s,"note":"%s"' \
  "$(esc "$ts")" "$(esc "$project")" "$(esc "$agent")" "$(esc "$model")" \
  "$(esc "$verdict")" "$(esc "$metric")" "$retry" "$(esc "$note")")"
[ -n "$tokens_in" ]  && line="$line,\"tokens_in\":$tokens_in"
[ -n "$tokens_out" ] && line="$line,\"tokens_out\":$tokens_out"
[ -n "$tokens_cached" ] && line="$line,\"tokens_cached\":$tokens_cached"
[ -n "$tokens_reasoning" ] && line="$line,\"tokens_reasoning\":$tokens_reasoning"
[ -n "$cost" ]       && line="$line,\"cost\":\"$(esc "$cost")\""
[ -n "$cost_usd" ]   && line="$line,\"cost_usd\":$cost_usd"
[ -n "$duration_ms" ] && line="$line,\"duration_ms\":$duration_ms"
[ -n "$usage_source" ] && line="$line,\"usage_source\":\"$usage_source\""
[ -n "$correlation_id" ] && line="$line,\"correlation_id\":\"$(esc "$correlation_id")\""
printf '%s}\n' "$line" >> "$log"

total="$(cat "$runs_dir"/*.jsonl 2>/dev/null | grep -c '"agent"' || true)"
case "$total" in ''|*[!0-9]*) total=0 ;; esac
printf '{"ok":true,"log":"%s","events_total":%d}\n' "$(esc "$log")" "$total"
