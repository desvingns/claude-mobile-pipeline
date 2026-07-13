#!/usr/bin/env bash
# mp-brain-memory.sh — safe gateway between a generated /mp pipeline and
# the shared second brain. Curated files are READ-ONLY. Cross-project writes are always
# staged as fingerprinted candidates in brain/inbox/ for human promotion.
#
# Commands (each emits exactly one JSON line):
#   resolve [--brain <root>]
#   context --tags <csv> [--budget <tokens>] [--max-files N] [--brain <root>]
#   append-candidate --kind user-preference|brain-level --project <name>
#     --text <lesson> --evidence <provenance> [--scope core|domain|pipeline|project]
#     [--suggested-file brain/<curated-path>.md] [--source <agent>] [--brain <root>]
#     [--dry-run]
set -uo pipefail

emit() { printf '%s\n' "$1"; exit "${2:-0}"; }
json_escape() {
  printf '%s' "$1" | awk 'BEGIN { ORS="" }
    { gsub(/\\/, "\\\\"); gsub(/"/, "\\\""); gsub(/\t/, "\\t");
      if (NR > 1) printf "\\n"; printf "%s", $0 }'
}
one_line() { printf '%s' "$1" | tr '\r\n\t' '   ' | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//'; }
lower_words() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9_-]+/ /g; s/[[:space:]]+/ /g; s/^ //; s/ $//'; }

excluded_by_policy() {
  local value="$1" pattern="" pattern_file
  if [ -n "${BRAIN_EXCLUDE_RE:-}" ]; then
    pattern="$BRAIN_EXCLUDE_RE"
  else
    pattern_file="${BRAIN_EXCLUDE_FILE:-$HOME/.config/brain/exclude-pattern.txt}"
    if [ -f "$pattern_file" ]; then
      pattern=$(awk '
        /^[[:space:]]*(#|$)/ { next }
        { if (combined != "") combined=combined "|"; combined=combined "(" $0 ")" }
        END { print combined }
      ' "$pattern_file" | tr -d '\r')
    fi
  fi
  [ -n "$pattern" ] || return 1
  printf ' %s ' "$value" | grep -Eiq -- "$pattern"
}

brain_override=""
resolve_brain() {
  local candidate pointer
  if [ -n "$brain_override" ]; then
    [ -d "$brain_override" ] && printf '%s' "$brain_override"
    return
  fi
  if [ -n "${BRAIN:-}" ] && [ -d "$BRAIN" ]; then
    printf '%s' "$BRAIN"; return 0
  fi
  pointer="$HOME/.config/brain/root"
  if [ -f "$pointer" ]; then
    IFS= read -r candidate < "$pointer" || true
    candidate=$(printf '%s' "$candidate" | tr -d '\r')
    if [ -n "$candidate" ] && [ -d "$candidate" ]; then
      printf '%s' "$candidate"; return 0
    fi
  fi
  for candidate in /d/Pet/brain D:/Pet/brain /c/Pet/brain C:/Pet/brain; do
    if [ -d "$candidate" ]; then printf '%s' "$candidate"; return 0; fi
  done
  return 1
}

resolve_profile() { # read path only — this function never creates or modifies it
  local brain="$1" legacy="$HOME/.config/mobile-pipeline/user-profile.md"
  if [ -n "${MP_USER_PROFILE:-}" ] && [ -f "$MP_USER_PROFILE" ]; then
    printf '%s' "$MP_USER_PROFILE"
  elif [ -n "$brain" ] && [ -f "$brain/core/user-profile.md" ]; then
    printf '%s' "$brain/core/user-profile.md"
  elif [ -f "$legacy" ]; then
    printf '%s' "$legacy"
  fi
}

hash_text() {
  local value="$1" out
  if command -v sha256sum >/dev/null 2>&1; then
    out=$(printf '%s' "$value" | sha256sum); out=${out%% *}
  elif command -v shasum >/dev/null 2>&1; then
    out=$(printf '%s' "$value" | shasum -a 256); out=${out%% *}
  elif command -v openssl >/dev/null 2>&1; then
    out=$(printf '%s' "$value" | openssl dgst -sha256 2>/dev/null); out=${out##* }
  else
    out=$(printf '%s' "$value" | cksum); out=${out%% *}
  fi
  printf '%s' "$out"
}

cmd_resolve() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --brain) [ $# -ge 2 ] || emit '{"ok":false,"error":"--brain needs a value"}' 2; brain_override="$2"; shift 2 ;;
      *) emit "{\"ok\":false,\"error\":\"unknown arg: $(json_escape "$1")\"}" 2 ;;
    esac
  done
  local brain="" profile="" inbox=""
  brain=$(resolve_brain || true)
  profile=$(resolve_profile "$brain")
  [ -n "$brain" ] && inbox="$brain/inbox"
  emit "{\"ok\":true,\"brain_root\":\"$(json_escape "$brain")\",\"profile_read\":\"$(json_escape "$profile")\",\"profile_read_only\":true,\"candidate_write\":\"$(json_escape "$inbox")\",\"curated_writes\":false}"
}

cmd_context() {
  local tags="" budget=900 max_files=3 brain="" profile="" cap
  while [ $# -gt 0 ]; do
    case "$1" in
      --tags) [ $# -ge 2 ] || emit '{"ok":false,"error":"--tags needs a value"}' 2; tags="$2"; shift 2 ;;
      --budget) [ $# -ge 2 ] || emit '{"ok":false,"error":"--budget needs a value"}' 2; budget="$2"; shift 2 ;;
      --max-files) [ $# -ge 2 ] || emit '{"ok":false,"error":"--max-files needs a value"}' 2; max_files="$2"; shift 2 ;;
      --brain) [ $# -ge 2 ] || emit '{"ok":false,"error":"--brain needs a value"}' 2; brain_override="$2"; shift 2 ;;
      *) emit "{\"ok\":false,\"error\":\"unknown arg: $(json_escape "$1")\"}" 2 ;;
    esac
  done
  [ -n "$tags" ] || emit '{"ok":false,"error":"--tags is required (on-demand selection never bulk-loads the brain)"}' 2
  case "$budget" in ''|*[!0-9]*) emit '{"ok":false,"error":"--budget must be an integer"}' 2 ;; esac
  case "$max_files" in ''|*[!0-9]*) emit '{"ok":false,"error":"--max-files must be an integer"}' 2 ;; esac
  [ "$budget" -ge 50 ] || budget=50
  cap="${BRAIN_CONTEXT_MAX_TOKENS:-1600}"
  case "$cap" in ''|*[!0-9]*) cap=1600 ;; esac
  [ "$cap" -ge 50 ] || cap=50
  [ "$budget" -le "$cap" ] || budget="$cap"
  [ "$max_files" -ge 1 ] || max_files=1
  [ "$max_files" -le 5 ] || max_files=5

  brain=$(resolve_brain || true)
  [ -n "$brain" ] || emit "{\"ok\":true,\"brain_root\":\"\",\"files\":[],\"budget_tokens\":$budget,\"approx_tokens\":0,\"context\":\"\",\"reason\":\"brain unavailable\"}"
  profile=$(resolve_profile "$brain")

  local words tag line link score lower ranked="" path rel context="" header body piece
  local max_chars=$((budget * 4)) remaining files_json="" count=0
  local -a selected=()
  words=$(lower_words "$tags")

  case " $words " in
    *" user "*|*" preference "*|*" profile "*|*" taste "*|*" design "*|*" ui "*|*" feedback "*|*" language "*)
      [ -n "$profile" ] && selected+=("$profile")
      ;;
  esac

  if [ -f "$brain/INDEX.md" ]; then
    while IFS= read -r line; do
      link=$(printf '%s\n' "$line" | sed -nE 's/^- \[[^]]+\]\(([^)]+)\).*/\1/p')
      case "$link" in domains/*.md|pipelines/*.md|projects/*.md|decisions/*.md) ;; *) continue ;; esac
      lower=$(lower_words "$line $link")
      score=0
      for tag in $words; do
        [ "${#tag}" -ge 3 ] || continue
        case " $lower " in *"$tag"*) score=$((score + 1)) ;; esac
      done
      if [ "$score" -gt 0 ]; then
        ranked="${ranked}$(printf '%04d\t%s' "$score" "$link")"$'\n'
      fi
    done < "$brain/INDEX.md"
  fi

  while IFS=$'\t' read -r score link; do
    [ -n "$link" ] || continue
    [ "${#selected[@]}" -lt "$max_files" ] || break
    path="$brain/$link"; [ -f "$path" ] || continue
    selected+=("$path")
  done < <(printf '%s' "$ranked" | sort -r)

  for path in "${selected[@]}"; do
    [ "$count" -lt "$max_files" ] || break
    remaining=$((max_chars - ${#context}))
    [ "$remaining" -gt 32 ] || break
    case "$path" in "$brain"/*) rel=${path#"$brain"/} ;; *) rel=$path ;; esac
    header="## source: $rel"
    body=$(< "$path")
    piece="$header
$body
"
    if [ "${#piece}" -gt "$remaining" ]; then
      [ "$remaining" -gt 20 ] || break
      piece="${piece:0:$((remaining - 16))}
[truncated]
"
    fi
    context="$context$piece"
    [ -n "$files_json" ] && files_json="$files_json,"
    files_json="$files_json\"$(json_escape "$rel")\""
    count=$((count + 1))
  done
  local approx=$(( (${#context} + 3) / 4 ))
  emit "{\"ok\":true,\"brain_root\":\"$(json_escape "$brain")\",\"files\":[$files_json],\"budget_tokens\":$budget,\"approx_tokens\":$approx,\"context\":\"$(json_escape "$context")\"}"
}

cmd_append_candidate() { # fire-and-forget: all outcomes are one JSON line + exit 0
  local kind="" project="" text_value="" evidence="" scope="" suggested="" source="mp-knowledge"
  local dry_run=0 brain="" inbox="" normalized="" digest="" candidate_id="" slug="" date_tag ts file title=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --kind) [ $# -ge 2 ] || emit '{"ok":false,"queued":false,"curated_writes":false,"error":"--kind needs a value"}'; kind="$2"; shift 2 ;;
      --project) [ $# -ge 2 ] || emit '{"ok":false,"queued":false,"curated_writes":false,"error":"--project needs a value"}'; project="$2"; shift 2 ;;
      --text) [ $# -ge 2 ] || emit '{"ok":false,"queued":false,"curated_writes":false,"error":"--text needs a value"}'; text_value="$2"; shift 2 ;;
      --evidence) [ $# -ge 2 ] || emit '{"ok":false,"queued":false,"curated_writes":false,"error":"--evidence needs a value"}'; evidence="$2"; shift 2 ;;
      --scope) [ $# -ge 2 ] || emit '{"ok":false,"queued":false,"curated_writes":false,"error":"--scope needs a value"}'; scope="$2"; shift 2 ;;
      --suggested-file) [ $# -ge 2 ] || emit '{"ok":false,"queued":false,"curated_writes":false,"error":"--suggested-file needs a value"}'; suggested="$2"; shift 2 ;;
      --source) [ $# -ge 2 ] || emit '{"ok":false,"queued":false,"curated_writes":false,"error":"--source needs a value"}'; source="$2"; shift 2 ;;
      --brain) [ $# -ge 2 ] || emit '{"ok":false,"queued":false,"curated_writes":false,"error":"--brain needs a value"}'; brain_override="$2"; shift 2 ;;
      --dry-run) dry_run=1; shift ;;
      *) emit "{\"ok\":false,\"queued\":false,\"curated_writes\":false,\"error\":\"unknown arg: $(json_escape "$1")\"}" ;;
    esac
  done
  case "$kind" in user-preference|brain-level) ;; *) emit '{"ok":false,"queued":false,"curated_writes":false,"error":"--kind must be user-preference or brain-level"}' ;; esac
  [ -n "$text_value" ] || emit '{"ok":false,"queued":false,"curated_writes":false,"error":"--text is required"}'
  [ -n "$evidence" ] || emit '{"ok":false,"queued":false,"curated_writes":false,"error":"--evidence is required"}'
  [ -n "$project" ] || project=$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")
  if [ "$kind" = user-preference ]; then
    scope=core; [ -n "$suggested" ] || suggested="brain/core/user-profile.md"
  else
    [ -n "$scope" ] || scope=domain
  fi
  case "$scope" in core|domain|pipeline|project) ;; *) emit '{"ok":false,"queued":false,"curated_writes":false,"error":"invalid --scope"}' ;; esac
  case "$suggested" in
    "") ;;
    *..*) emit '{"ok":false,"queued":false,"curated_writes":false,"error":"--suggested-file cannot contain .."}' ;;
    brain/core/*.md|brain/domains/*.md|brain/pipelines/*.md|brain/projects/*.md) ;;
    *) emit '{"ok":false,"queued":false,"curated_writes":false,"error":"--suggested-file must name a curated brain markdown path"}' ;;
  esac

  text_value=$(one_line "$text_value"); evidence=$(one_line "$evidence"); project=$(one_line "$project"); source=$(one_line "$source")
  normalized=$(lower_words "$text_value $evidence $project $source")
  excluded_by_policy "$normalized"
  exclusion_status=$?
  case "$exclusion_status" in
    0) emit '{"ok":false,"queued":false,"curated_writes":false,"error":"candidate rejected by the local exclusion policy"}' ;;
    1) ;;
    *) emit '{"ok":false,"queued":false,"curated_writes":false,"error":"invalid local exclusion policy"}' ;;
  esac
  # Evidence participates in the id: retries of the same capture dedupe, while a later
  # independent signal remains separate corroboration for the human promotion gate.
  digest=$(hash_text "$kind|$(lower_words "$project")|$(lower_words "$text_value")|$(lower_words "$evidence")")
  candidate_id="cand-${digest:0:16}"
  brain=$(resolve_brain || true)
  [ -n "$brain" ] || emit "{\"ok\":false,\"queued\":false,\"candidate_id\":\"$candidate_id\",\"curated_writes\":false,\"error\":\"brain unavailable; return the candidate to the orchestrator without writing elsewhere\"}"
  inbox="$brain/inbox"
  if grep -R -F -- "- id: $candidate_id" "$inbox"/*.md >/dev/null 2>&1; then
    emit "{\"ok\":true,\"queued\":true,\"deduplicated\":true,\"candidate_id\":\"$candidate_id\",\"curated_writes\":false}"
  fi

  date_tag=$(date -u +%Y-%m-%d); ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  slug=$(printf '%s' "$project" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')
  [ -n "$slug" ] || slug=unknown-project
  file="$inbox/$date_tag-$slug.md"
  title=${text_value:0:72}
  if [ "$dry_run" -eq 1 ]; then
    emit "{\"ok\":true,\"queued\":false,\"dry_run\":true,\"candidate_id\":\"$candidate_id\",\"file\":\"inbox/$(json_escape "$(basename "$file")")\",\"curated_writes\":false}"
  fi

  mkdir -p "$inbox" || emit '{"ok":false,"queued":false,"curated_writes":false,"error":"cannot create brain inbox"}'
  if [ ! -f "$file" ]; then printf '# Brain candidates — %s\n\n' "$date_tag" >> "$file"; fi
  {
    printf '## %s %s — %s\n' "$date_tag" "$project" "$title"
    printf '%s\n' "- id: $candidate_id"
    printf '%s\n' "- kind: $kind"
    printf '%s\n' "- scope: $scope"
    printf '%s\n' "- text: $text_value"
    printf '%s\n' "- evidence: $evidence"
    [ -n "$suggested" ] && printf '%s\n' "- suggested_file: $suggested"
    printf '%s\n' "- source: $source"
    printf '%s\n' "- captured_at: $ts"
    printf '%s\n\n' '- status: NEW'
  } >> "$file" || emit '{"ok":false,"queued":false,"curated_writes":false,"error":"cannot append candidate"}'
  emit "{\"ok\":true,\"queued\":true,\"deduplicated\":false,\"candidate_id\":\"$candidate_id\",\"file\":\"inbox/$(json_escape "$(basename "$file")")\",\"curated_writes\":false}"
}

command_name="${1:-resolve}"
[ $# -gt 0 ] && shift
case "$command_name" in
  resolve) cmd_resolve "$@" ;;
  context) cmd_context "$@" ;;
  append-candidate) cmd_append_candidate "$@" ;;
  -h|--help|help) sed -n '2,12p' "$0"; exit 0 ;;
  *) emit "{\"ok\":false,\"error\":\"unknown command: $(json_escape "$command_name")\"}" 2 ;;
esac
