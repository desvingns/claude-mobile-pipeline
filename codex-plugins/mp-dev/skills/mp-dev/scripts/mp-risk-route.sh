#!/usr/bin/env bash
# mp-risk-route.sh — deterministic risk/model/quality routing for /mp.
# Emits exactly one JSON line; it never edits the project.
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

task="feature"
spec=""
visual=false
# A sentinel keeps Bash 3.2 + `set -u` from treating an empty array expansion as unbound.
files=("")
file_count=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --task) [ "$#" -ge 2 ] || emit_error "--task requires feature or bugfix"; task="$2"; shift 2 ;;
    --spec) [ "$#" -ge 2 ] || emit_error "--spec requires a file"; spec="$2"; shift 2 ;;
    --changed) [ "$#" -ge 2 ] || emit_error "--changed requires a path"; files+=("$2"); file_count=$((file_count + 1)); shift 2 ;;
    --visual) visual=true; shift ;;
    --) shift; while [ "$#" -gt 0 ]; do files+=("$1"); file_count=$((file_count + 1)); shift; done ;;
    *) files+=("$1"); file_count=$((file_count + 1)); shift ;;
  esac
done

case "$task" in feature|bugfix) ;; *) emit_error "--task must be feature or bugfix" ;; esac
[ -n "$spec" ] || emit_error "--spec is required"
[ -f "$spec" ] || emit_error "spec file not found: $spec"

score=0
signals=""
add_signal() {
  local points="$1" signal="$2"
  score=$((score + points))
  [ -n "$signals" ] && signals="$signals;"
  signals="$signals$signal"
}

text=$(tr '\n' ' ' < "$spec")
if printf '%s' "$text" | grep -Eiq 'migration|schema|database|room|datastore|serialization|backward.?compat'; then
  add_signal 4 persistence_or_migration
fi
if printf '%s' "$text" | grep -Eiq 'security|privacy|authentication|authorization|payment|billing|crypto|permission|secret|token'; then
  add_signal 4 security_or_payment
fi
if printf '%s' "$text" | grep -Eiq 'navigation|deep.?link|hilt|dependency injection|manifest|gradle|build logic'; then
  add_signal 3 wiring_or_build
fi
if printf '%s' "$text" | grep -Eiq 'offline|concurren|race|transaction|idempot|sync|background'; then
  add_signal 2 state_or_concurrency
fi

layers=""
for file in "${files[@]}"; do
  [ -n "$file" ] || continue
  case "$file" in
    *[Mm]igration*|*schema*|*room*|*database*) add_signal 4 persistence_file ;;
    *AndroidManifest.xml|*.gradle|*.gradle.kts|*libs.versions.toml|*Hilt*Module*|*Navigation*) add_signal 3 wiring_file ;;
  esac
  case "$file" in
    *presentation*|*ui*) layers="${layers}p" ;;
    *domain*|*usecase*|*UseCase*) layers="${layers}d" ;;
    *data*|*repository*|*dao*|*entity*) layers="${layers}a" ;;
  esac
done

unique_layers=$(printf '%s' "$layers" | fold -w1 | LC_ALL=C sort -u | tr -d '\n')
[ "${#unique_layers}" -ge 2 ] && add_signal 2 cross_layer
[ "$file_count" -gt 8 ] && add_signal 2 broad_diff
[ "$visual" = true ] && add_signal 2 visual_device_evidence
[ -z "$signals" ] && signals="routine_local_change"

risk=low
developer_tier=standard
semantic_review=false
critic=false
if [ "$score" -ge 7 ]; then
  risk=high; developer_tier=powerful; semantic_review=true; critic=true
elif [ "$score" -ge 3 ]; then
  risk=standard; semantic_review=true
fi

verifier=full
if [ "$task" = "bugfix" ] && [ "$risk" = "low" ]; then verifier=lite; fi

printf '{"ok":true,"risk":"%s","score":%s,"developer_tier":"%s","semantic_review":%s,"verifier":"%s","independent_critic":%s,"signals":"%s"}\n' \
  "$risk" "$score" "$developer_tier" "$semantic_review" "$verifier" "$critic" "$(json_escape "$signals")"
