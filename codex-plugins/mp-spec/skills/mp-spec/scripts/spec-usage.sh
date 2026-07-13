#!/usr/bin/env bash
# spec-usage.sh — append one normalized MP Spec agent-usage event.
# Missing provider token counts may be estimated from character counts, but are always labelled.
set -uo pipefail

json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"; s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"; s="${s//$'\r'/\\r}"; s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

emit_error() {
  printf '{"ok":false,"error":"%s"}\n' "$(json_escape "$1")"
  exit 0
}

usage_file="${1:-}"
[ -n "$usage_file" ] || emit_error "usage: spec-usage.sh <agent-usage.jsonl> --role <role> --phase <phase> [fields]"
case "$usage_file" in
  -*) emit_error "usage file must be the first positional argument" ;;
esac
shift
role=""; phase=""; model="unknown"; reasoning="unknown"; correlation=""
input_tokens=""; output_tokens=""; cached_tokens=0; reasoning_tokens=0
input_chars=""; output_chars=""; duration_ms=0; retry=0; cache_hit=false; status=ok

require_option_value() {
  local option="$1"
  [ "$#" -ge 2 ] || emit_error "$option requires a value"
  [ -n "$2" ] || emit_error "$option requires a non-empty value"
  case "$2" in
    --*) emit_error "$option requires a value" ;;
  esac
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --role) require_option_value "$@"; role="$2"; shift 2 ;;
    --phase) require_option_value "$@"; phase="$2"; shift 2 ;;
    --model) require_option_value "$@"; model="$2"; shift 2 ;;
    --reasoning) require_option_value "$@"; reasoning="$2"; shift 2 ;;
    --correlation) require_option_value "$@"; correlation="$2"; shift 2 ;;
    --input-tokens) require_option_value "$@"; input_tokens="$2"; shift 2 ;;
    --output-tokens) require_option_value "$@"; output_tokens="$2"; shift 2 ;;
    --cached-tokens) require_option_value "$@"; cached_tokens="$2"; shift 2 ;;
    --reasoning-tokens) require_option_value "$@"; reasoning_tokens="$2"; shift 2 ;;
    --input-chars) require_option_value "$@"; input_chars="$2"; shift 2 ;;
    --output-chars) require_option_value "$@"; output_chars="$2"; shift 2 ;;
    --duration-ms) require_option_value "$@"; duration_ms="$2"; shift 2 ;;
    --retry) require_option_value "$@"; retry="$2"; shift 2 ;;
    --cache-hit) require_option_value "$@"; cache_hit="$2"; shift 2 ;;
    --status) require_option_value "$@"; status="$2"; shift 2 ;;
    *) emit_error "unknown argument: $1" ;;
  esac
done
[ -n "$role" ] || emit_error "--role is required"
[ -n "$phase" ] || emit_error "--phase is required"

is_uint() { printf '%s' "$1" | grep -Eq '^[0-9]+$'; }
for value in "$cached_tokens" "$reasoning_tokens" "$duration_ms" "$retry"; do
  is_uint "$value" || emit_error "numeric fields must be unsigned integers"
done
case "$cache_hit" in true|false) ;; *) emit_error "--cache-hit must be true or false" ;; esac

estimated=false
if [ -z "$input_tokens" ]; then
  [ -n "$input_chars" ] && is_uint "$input_chars" || emit_error "provide --input-tokens or --input-chars"
  input_tokens=$(((input_chars + 3) / 4)); estimated=true
else
  is_uint "$input_tokens" || emit_error "--input-tokens must be an unsigned integer"
fi
if [ -z "$output_tokens" ]; then
  [ -n "$output_chars" ] && is_uint "$output_chars" || emit_error "provide --output-tokens or --output-chars"
  output_tokens=$(((output_chars + 3) / 4)); estimated=true
else
  is_uint "$output_tokens" || emit_error "--output-tokens must be an unsigned integer"
fi

[ -n "$correlation" ] || correlation="spec-$(date -u +%Y%m%dT%H%M%SZ)-$$"
stamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
event=$(printf '{"ts":"%s","correlation_id":"%s","phase":"%s","role":"%s","model":"%s","reasoning":"%s","tokens":{"input":%s,"output":%s,"cached":%s,"reasoning":%s},"estimated":%s,"duration_ms":%s,"retry":%s,"cache_hit":%s,"status":"%s"}' \
  "$stamp" "$(json_escape "$correlation")" "$(json_escape "$phase")" "$(json_escape "$role")" \
  "$(json_escape "$model")" "$(json_escape "$reasoning")" "$input_tokens" "$output_tokens" \
  "$cached_tokens" "$reasoning_tokens" "$estimated" "$duration_ms" "$retry" "$cache_hit" "$(json_escape "$status")")
mkdir -p "$(dirname "$usage_file")" || emit_error "cannot create usage directory"
printf '%s\n' "$event" >> "$usage_file" || emit_error "cannot append usage event"
printf '{"ok":true,"file":"%s","correlation_id":"%s","estimated":%s,"input_tokens":%s,"output_tokens":%s}\n' \
  "$(json_escape "$usage_file")" "$(json_escape "$correlation")" "$estimated" "$input_tokens" "$output_tokens"
