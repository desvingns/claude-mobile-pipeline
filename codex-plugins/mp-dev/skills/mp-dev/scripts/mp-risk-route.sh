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
# Each signal counts once. It represents a kind of risk present in the change, not
# how many files exhibit it: scoring it per file made the route a function of diff
# size, and the same concern reached from two directions (a file name and the file
# content, a declared tag and the prose) must not be paid for twice.
add_signal() {
  local points="$1" signal="$2"
  case ";$signals;" in *";$signal;"*) return 0 ;; esac
  score=$((score + points))
  [ -n "$signals" ] && signals="$signals;"
  signals="$signals$signal"
}

text=$(tr '\n' ' ' < "$spec")

# ---- Declared signals (authoritative) ----------------------------------
# A SPEC may carry `Risk-signals: auth, di-wiring, concurrency` in its front
# matter. Prose keyword matching is a fallback, not the primary input: it is
# language-bound, and a SPEC written in the team's own language scored as
# routine work while crossing auth, DI, and concurrency at once. What the
# planner already knows about a slice should not have to be re-inferred from
# the wording it happened to use.
declared=$(grep -aiE '^[[:space:]]*Risk-signals:' "$spec" 2>/dev/null | head -1 |
           sed -e 's/^[^:]*://' -e 's/[,;]/ /g' | tr 'A-Z' 'a-z')
declared_seen=""
for token in $declared; do
  case " $declared_seen " in *" $token "*) continue ;; esac
  declared_seen="$declared_seen $token"
  case "$token" in
    auth|authentication|session|entitlement|payment|billing|security|privacy|secret)
      add_signal 4 security_or_payment ;;
    persistence|migration|schema|storage)
      add_signal 4 persistence_or_migration ;;
    di-wiring|di|wiring|hilt|navigation|build)
      add_signal 3 wiring_or_build ;;
    concurrency|server-authoritative|offline|sync|cancellation)
      add_signal 2 state_or_concurrency ;;
    cross-module|cross-layer)
      add_signal 2 cross_layer ;;
    visual)
      add_signal 2 visual_device_evidence ;;
  esac
done

# ---- Prose keywords (fallback for hand-written SPECs) -------------------
# English patterns use -i; the non-English ones spell both cases out, because
# case-insensitive matching outside ASCII depends on the locale and this script
# has to behave the same on Linux, macOS, and Git Bash.
ru_persistence='[Мм]играци|[Бб]аз[аые] данных|[Сс]хем[аыуе] (данных|базы|таблиц)|[Сс]ериализац|[Хх]ранилищ|[Оо]братн.{0,3} совместимост'
ru_security='[Бб]езопасност|[Пп]риватн|[Аа]утентификац|[Аа]вторизац|[Пп]лат[её]ж|[Пп]одписк|[Бб]иллинг|[Шш]ифрован|[Рр]азрешени|[Сс]екрет|[Тт]окен|[Сс]есси|[Уу]ч[ёе]тн'
ru_wiring='[Нн]авигац|[Дд]иплинк|[Гг]лубок.{0,4}ссылк|[Вв]недрени[ея] зависимост|[Мм]анифест|[Сс]борк|[Гг]раф зависимост'
ru_state='[Оо]флайн|[Оо]ффлайн|[Кк]онкурент|[Гг]онк|[Тт]ранзакц|[Ии]демпотент|[Сс]инхронизац|[Фф]онов|[Пп]оллинг|[Кк]орутин|[Оо]тмен[аыу]|[Тт]аймаут'

if printf '%s' "$text" | grep -Eiq 'migration|schema|database|room|datastore|serialization|backward.?compat' ||
   printf '%s' "$text" | grep -Eq "$ru_persistence"; then
  add_signal 4 persistence_or_migration
fi
if printf '%s' "$text" | grep -Eiq 'security|privacy|authentication|authorization|payment|billing|crypto|permission|secret|token|entitlement' ||
   printf '%s' "$text" | grep -Eq "$ru_security"; then
  add_signal 4 security_or_payment
fi
if printf '%s' "$text" | grep -Eiq 'navigation|deep.?link|hilt|dependency injection|manifest|gradle|build logic' ||
   printf '%s' "$text" | grep -Eq "$ru_wiring"; then
  add_signal 3 wiring_or_build
fi
if printf '%s' "$text" | grep -Eiq 'offline|concurren|race|transaction|idempot|sync|background|polling|cancellation|timeout' ||
   printf '%s' "$text" | grep -Eq "$ru_state"; then
  add_signal 2 state_or_concurrency
fi

# ---- Changed-file signals ----------------------------------------------
# Kotlin/Swift sources are PascalCase, so the old lowercase globs
# (*repository*, *database*, *Hilt*Module*) never matched a real file name and
# these signals could not fire at all. Names are matched case-insensitively and
# DI/persistence are confirmed from file content, which does not depend on how
# the author chose to name the class.
layers=""
for file in "${files[@]}"; do
  [ -n "$file" ] || continue
  lower=$(printf '%s' "$file" | tr 'A-Z' 'a-z')
  case "$lower" in
    *migration*|*schema*|*room*|*database*|*dao*|*entity*) add_signal 4 persistence_file ;;
  esac
  case "$lower" in
    *androidmanifest.xml|*.gradle|*.gradle.kts|*libs.versions.toml|*module.kt|*navigation*|*/di/*)
      add_signal 3 wiring_file ;;
  esac
  if [ -f "$file" ]; then
    if grep -qE '@(Module|InstallIn|Provides|Binds)\b|dagger\.hilt' "$file" 2>/dev/null; then
      add_signal 3 wiring_file
    fi
    if grep -qE '@(Database|Dao|Entity|TypeConverter)\b|androidx\.room|Migration\(' "$file" 2>/dev/null; then
      add_signal 4 persistence_file
    fi
  fi
  case "$lower" in
    *presentation*|*/ui/*) layers="${layers}p" ;;
  esac
  case "$lower" in
    */domain/*|*usecase*) layers="${layers}d" ;;
  esac
  case "$lower" in
    */data/*|*repository*|*dao*|*entity*) layers="${layers}a" ;;
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

# Security/entitlement work that also touches state, wiring, or persistence takes
# the strong route regardless of total score. Getting auth or entitlement wrong is
# not a risk that scales with diff size, and a change carrying both concerns at
# once is exactly the shape that costs several review/repair cycles to converge.
case ";$signals;" in
  *";security_or_payment;"*)
    case ";$signals;" in
      *";state_or_concurrency;"*|*";wiring_or_build;"*|*";wiring_file;"*|\
      *";persistence_or_migration;"*|*";persistence_file;"*|*";cross_layer;"*)
        risk=high; developer_tier=powerful; semantic_review=true; critic=true
        add_signal 0 security_combination
        ;;
    esac
    ;;
esac

verifier=full
if [ "$task" = "bugfix" ] && [ "$risk" = "low" ]; then verifier=lite; fi

printf '{"ok":true,"risk":"%s","score":%s,"developer_tier":"%s","semantic_review":%s,"verifier":"%s","independent_critic":%s,"signals":"%s"}\n' \
  "$risk" "$score" "$developer_tier" "$semantic_review" "$verifier" "$critic" "$(json_escape "$signals")"
