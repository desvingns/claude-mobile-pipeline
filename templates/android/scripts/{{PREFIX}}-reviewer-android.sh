#!/usr/bin/env bash
# {{PREFIX}}-reviewer-android.sh — Clean Architecture layer-boundary checks for {{PROJECT_NAME}}.
# Emits exactly one JSON line on stdout. No prose, no progress output.
#
# Usage:
#   {{PREFIX}}-reviewer-android.sh [--warn-only] <file1> <file2> ...
#   echo -e "file1\nfile2" | {{PREFIX}}-reviewer-android.sh [--warn-only]
#
# Paths in CHANGED_FILES are relative to repo root. Pre-existing violations in
# files NOT listed are ignored, per the agent contract.
#
# Layout support: both the single-module layout (app/src/main/java/<pkg>/<layer>/…)
# and the multi-module layout (core/<name>/src/main/{java,kotlin}/<pkg>/…,
# feature/<name>/src/main/…). Layers are resolved from the path instead of from
# one hard-coded source root: gating every check on app/src/main/java/<pkg> made
# this gate a silent no-op on multi-module projects, so architectural findings had
# to be rediscovered one at a time by the expensive semantic reviewer.
#
# --warn-only: report findings under "warnings" and keep pass=true. Use when
# enabling newly-widened checks on a codebase they have never run against, so a
# backlog of pre-existing findings cannot block the pipeline on day one.
#
# Output (clear):    {"pass":true,"violations":[],"warnings":[],"by_check":{}}
# Output (failure):  {"pass":false,"violations":["<path>:<line> — <msg>", ...],"warnings":[],"by_check":{"<id>":N}}

set -uo pipefail

PACKAGE="{{PACKAGE}}"
SRC_ROOT="app/src/main/java/{{PACKAGE_PATH}}"

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf '{"pass":false,"violations":["not a git repo"],"warnings":[],"by_check":{}}\n'
  exit 0
}
cd "$REPO_ROOT"

# ----- collect flags + CHANGED_FILES from args, or stdin if no args ------
WARN_ONLY=0
CHANGED=()
ARG_COUNT=0
for a in "$@"; do
  case "$a" in
    --warn-only) WARN_ONLY=1 ;;
    '') ;;
    *) CHANGED+=("$a"); ARG_COUNT=$((ARG_COUNT + 1)) ;;
  esac
done

if [ "$ARG_COUNT" -eq 0 ] && [ -p /dev/stdin ]; then
  while IFS= read -r line; do
    [ -n "$line" ] && CHANGED+=("$line")
  done
fi

# ----- JSON helpers ------------------------------------------------------
json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

VIOLATIONS=()
CHECK_IDS=()
add_v() { CHECK_IDS+=("$1"); VIOLATIONS+=("$2"); }

# ----- Filter CHANGED to existing files only ----------------------------
EXISTING=()
for f in "${CHANGED[@]:-}"; do
  [ -n "$f" ] && [ -f "$f" ] && EXISTING+=("$f")
done

under() {
  case "$1" in
    "$2"*) return 0 ;;
    *)     return 1 ;;
  esac
}

# ----- Layout resolution -------------------------------------------------
# module_of <path> → gradle module dir ("app", "core/ads", "feature/dashboard"), or "".
module_of() {
  case "$1" in
    */src/*)                           printf '%s' "${1%%/src/*}" ;;
    */build.gradle.kts|*/build.gradle) printf '%s' "${1%/*}" ;;
    *)                                 printf '' ;;
  esac
}

# source_set_of <path> → main | test | androidTest | ""
source_set_of() {
  case "$1" in
    */src/androidTest/*) printf 'androidTest' ;;
    */src/test/*)        printf 'test' ;;
    */src/main/*)        printf 'main' ;;
    *)                   printf '' ;;
  esac
}

# layer_of <path> → domain | data | presentation | ""
# A path component named exactly domain/data/presentation/ui wins; otherwise a
# `feature/*` module is presentation by convention. Anything else stays unknown
# and is skipped rather than guessed at — a wrong layer guess produces false
# blockers, which is worse than no check.
layer_of() {
  case "/$1/" in
    */domain/*)              printf 'domain';       return ;;
    */data/*)                printf 'data';         return ;;
    */presentation/*|*/ui/*) printf 'presentation'; return ;;
  esac
  case "$(module_of "$1")" in
    feature/*|*/feature/*) printf 'presentation'; return ;;
  esac
  printf ''
}

# module_rank <module> → 1 domain, 2 other library, 3 feature, 4 app.
# A dependency edge from a lower rank to a higher rank inverts the layering.
module_rank() {
  case "$1" in
    app)                   printf '4' ;;
    feature/*|*/feature/*) printf '3' ;;
    */domain|domain)       printf '1' ;;
    *)                     printf '2' ;;
  esac
}

gradle_file_of() {
  if   [ -f "$1/build.gradle.kts" ]; then printf '%s' "$1/build.gradle.kts"
  elif [ -f "$1/build.gradle" ];     then printf '%s' "$1/build.gradle"
  else printf ''; fi
}

# direct_deps <module> → newline-separated dependency module dirs (":core:ads" → "core/ads").
direct_deps() {
  local gf; gf="$(gradle_file_of "$1")"
  [ -n "$gf" ] || return 0
  grep -oE "project\((\"|')[:][A-Za-z0-9_.:-]+(\"|')\)" "$gf" 2>/dev/null |
    sed -e 's/^project(.://' -e 's/.)$//' -e 's#:#/#g' |
    sort -u
}

# api_deps <module> → deps re-exported via api(project(...)); callers may import them transitively.
api_deps() {
  local gf; gf="$(gradle_file_of "$1")"
  [ -n "$gf" ] || return 0
  grep -oE "api\(project\((\"|')[:][A-Za-z0-9_.:-]+(\"|')\)\)" "$gf" 2>/dev/null |
    sed -e 's/^api(project(.://' -e 's/.))$//' -e 's#:#/#g' |
    sort -u
}

# effective_deps <module> → direct deps plus one level of api() re-exports.
effective_deps() {
  local m="$1" d
  direct_deps "$m"
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    api_deps "$d"
  done < <(direct_deps "$m")
}

# module_for_import <import-fqn> → owning module dir, or "".
# Maps <package>.core.ads.data.Foo → core/ads by taking the longest leading
# segment prefix that is an actual gradle module directory. Single-module
# projects resolve nothing here, which correctly makes the module checks inert.
MODULE_IMPORT_CACHE=""
module_for_import() {
  local fqn="$1" rest key esc cached seg path best i
  case "$fqn" in
    "$PACKAGE".*) rest="${fqn#"$PACKAGE".}" ;;
    *) printf ''; return ;;
  esac
  key="$rest"
  esc=$(printf '%s' "$key" | sed 's/[].[^$*\\]/\\&/g')
  cached=$(printf '%s' "$MODULE_IMPORT_CACHE" | grep -m1 -- "^${esc} " 2>/dev/null)
  if [ -n "$cached" ]; then printf '%s' "${cached#* }"; return; fi

  path=""; best=""; i=0
  while [ "$i" -lt 3 ]; do
    seg="${rest%%.*}"
    [ "$seg" = "$rest" ] && break
    if [ -n "$path" ]; then path="$path/$seg"; else path="$seg"; fi
    if [ -d "$path" ] && [ -n "$(gradle_file_of "$path")" ]; then best="$path"; fi
    rest="${rest#*.}"
    i=$((i + 1))
  done
  MODULE_IMPORT_CACHE="${MODULE_IMPORT_CACHE}${key} ${best}
"
  printf '%s' "$best"
}

# ----- Check 1: no Android imports in domain --------------------------
for f in "${EXISTING[@]:-}"; do
  [ -n "$f" ] || continue
  [ "$(layer_of "$f")" = domain ] || continue
  [ "$(source_set_of "$f")" = main ] || continue
  while IFS=: read -r line _; do
    [ -z "$line" ] && continue
    offending=$(sed -n "${line}p" "$f" | sed 's/^[[:space:]]*//')
    add_v "domain-purity" "$f:$line — illegal Android import in domain: $offending"
  done < <(grep -nE "^import android\." "$f" || true)
done

# ----- Check 2: no data layer imports in presentation -----------------
# Single-module projects expose the data layer as <package>.data.*; multi-module
# ones expose it as a separate gradle module whose own layer resolves to `data`.
for f in "${EXISTING[@]:-}"; do
  [ -n "$f" ] || continue
  [ "$(layer_of "$f")" = presentation ] || continue
  [ "$(source_set_of "$f")" = main ] || continue
  while IFS=: read -r line content; do
    [ -z "$line" ] && continue
    fqn=$(printf '%s' "$content" | sed -e 's/^[[:space:]]*import[[:space:]]*//' -e 's/[[:space:]].*$//' -e 's/\r$//')
    case "$fqn" in
      "$PACKAGE".data.*) ;;
      *)
        dep_module="$(module_for_import "$fqn")"
        [ -n "$dep_module" ] || continue
        [ "$(layer_of "$dep_module/src/main")" = data ] || continue
        ;;
    esac
    offending=$(printf '%s' "$content" | sed 's/^[[:space:]]*//')
    add_v "layer-boundary" "$f:$line — illegal data import in presentation: $offending"
  done < <(grep -nE "^import ${PACKAGE//./\\.}\." "$f" || true)
done

# ----- Check 3: ViewModels must not inject Repository -----------------
for f in "${EXISTING[@]:-}"; do
  [ -n "$f" ] || continue
  [ "$(layer_of "$f")" = presentation ] || continue
  case "${f##*/}" in
    *ViewModel.kt) ;;
    *) continue ;;
  esac
  while IFS=: read -r line content; do
    [ -z "$line" ] && continue
    case "$content" in
      *import\ *|*//*|*\*\ *) continue ;;
    esac
    offending=$(printf '%s' "$content" | sed 's/^[[:space:]]*//')
    add_v "layer-boundary" "$f:$line — ViewModel injects Repository directly (must go via UseCase): $offending"
  done < <(grep -nE ":\s*[A-Z][A-Za-z0-9_]*Repository\b" "$f" || true)
done

# ----- Check 4: Screen composables expose <Name>Content() -------------
for f in "${EXISTING[@]:-}"; do
  [ -n "$f" ] || continue
  [ "$(layer_of "$f")" = presentation ] || continue
  case "${f##*/}" in
    *Screen.kt) ;;
    *) continue ;;
  esac
  if ! grep -qE "^[[:space:]]*(public[[:space:]]+)?fun[[:space:]]+[A-Z][A-Za-z0-9_]*Content[[:space:]]*\(" "$f"; then
    add_v "screen-contract" "$f — missing public <Name>Content(...) composable; Screen wrappers must expose a testable Content body"
  fi
done

# ----- Check 5: no hardcoded UI values in presentation/ ---------------
# Tokens belong in ui/theme/ (Color.kt, Type.kt, Spacing.kt, Motion.kt). In screen
# code, reference via MaterialTheme.colorScheme.X, MaterialTheme.typography.X,
# LocalSpacing.current.X, LocalMotion.current.X.
# Allowlist for raw .dp: 0.dp (no padding) and 1.dp (hairline divider).
# The theme package itself is where the literals are supposed to live, so it is
# excluded — it only became reachable once `ui/` started resolving as presentation.
for f in "${EXISTING[@]:-}"; do
  [ -n "$f" ] || continue
  [ "$(layer_of "$f")" = presentation ] || continue
  [ "$(source_set_of "$f")" = main ] || continue
  case "$f" in
    */theme/*) continue ;;
  esac
  under "$f" "$SRC_ROOT/theme/" && continue

  # 5a — hardcoded Color(0x...) literals
  while IFS=: read -r line content; do
    [ -z "$line" ] && continue
    case "$content" in
      *//*|*\*\ *) continue ;;
    esac
    offending=$(printf '%s' "$content" | sed 's/^[[:space:]]*//')
    add_v "design-tokens" "$f:$line — hardcoded color literal; use MaterialTheme.colorScheme.X (see [[material3-design-tokens]]): $offending"
  done < <(grep -nE "Color\(0[xX]" "$f" || true)

  # 5b — raw .dp integer literals (allowlist: 0.dp, 1.dp)
  while IFS=: read -r line content; do
    [ -z "$line" ] && continue
    case "$content" in
      *//*|*\*\ *) continue ;;
    esac
    offending=$(printf '%s' "$content" | sed 's/^[[:space:]]*//')
    add_v "design-tokens" "$f:$line — raw .dp literal; use LocalSpacing.current.X (see [[spacing-scale-discipline]]): $offending"
  done < <(grep -nE "\b([2-9]|[0-9]{2,})\.dp\b" "$f" || true)

  # 5c — hardcoded fontSize = N.sp
  while IFS=: read -r line content; do
    [ -z "$line" ] && continue
    case "$content" in
      *//*|*\*\ *) continue ;;
    esac
    offending=$(printf '%s' "$content" | sed 's/^[[:space:]]*//')
    add_v "design-tokens" "$f:$line — hardcoded fontSize; use MaterialTheme.typography.X (see [[material3-design-tokens]]): $offending"
  done < <(grep -nE "fontSize[[:space:]]*=[[:space:]]*[0-9]+\.sp" "$f" || true)
done

# ----- Check 6: Test hygiene (every source set, not just app/) --------
# 6a — @Ignore without a TODO/#issue reference on the same or previous line.
# 6b — @Test with empty body (no assertion calls).
# 6c — Trivially-true assertions.
# 6d — Thread.sleep inside tests.
# 6e — runBlocking inside tests without an explicit real-I/O marker.
for f in "${EXISTING[@]:-}"; do
  [ -n "$f" ] || continue
  case "$f" in *.kt) ;; *) continue ;; esac
  case "$(source_set_of "$f")" in
    test|androidTest) ;;
    *) continue ;;
  esac

  # 6a — @Ignore without TODO/issue ref on same or previous line
  while IFS=: read -r line _; do
    [ -z "$line" ] && continue
    same=$(sed -n "${line}p" "$f")
    prev_no=$((line - 1))
    prev=""
    [ "$prev_no" -ge 1 ] && prev=$(sed -n "${prev_no}p" "$f")
    if ! printf '%s\n%s' "$same" "$prev" | grep -qE "TODO|#[0-9]+"; then
      offending=$(printf '%s' "$same" | sed 's/^[[:space:]]*//')
      add_v "test-hygiene" "$f:$line — @Ignore without TODO(#issue) reference: $offending"
    fi
  done < <(grep -nE "^[[:space:]]*@Ignore([[:space:]]|\()" "$f" || true)

  # 6b — @Test with no assertions anywhere in its body. The body ends at the next
  # JUnit annotation (or 200 lines out, whichever comes first): a fixed 20-line
  # window reported healthy long tests — with setup blocks or a dispatcher/latch
  # preamble — as assertion-free, and that noise is what makes a gate get ignored.
  while IFS=: read -r line _; do
    [ -z "$line" ] && continue
    next=$(awk -v s="$line" 'NR>s && /^[[:space:]]*@(Test|Before|After|BeforeClass|AfterClass|Ignore)\b/ {print NR; exit}' "$f")
    end=$((line + 200))
    if [ -n "$next" ] && [ "$next" -le "$end" ]; then end=$((next - 1)); fi
    body=$(sed -n "${line},${end}p" "$f")
    if ! printf '%s' "$body" | grep -qE "assert|expect|verify|should|Truth\."; then
      offending=$(sed -n "${line}p" "$f" | sed 's/^[[:space:]]*//')
      add_v "test-hygiene" "$f:$line — @Test with no assertions in body: $offending"
    fi
  done < <(grep -nE "^[[:space:]]*@Test[[:space:]]*$" "$f" || true)

  # 6c — Trivially-true assertions
  while IFS=: read -r line content; do
    [ -z "$line" ] && continue
    case "$content" in
      *//*) continue ;;
    esac
    offending=$(printf '%s' "$content" | sed 's/^[[:space:]]*//')
    add_v "test-hygiene" "$f:$line — trivially-true assertion: $offending"
  done < <(grep -nE "assertTrue\([[:space:]]*true[[:space:]]*\)|assertFalse\([[:space:]]*false[[:space:]]*\)" "$f" || true)

  # 6d — Thread.sleep
  while IFS=: read -r line content; do
    [ -z "$line" ] && continue
    case "$content" in
      *//*) continue ;;
    esac
    offending=$(printf '%s' "$content" | sed 's/^[[:space:]]*//')
    add_v "test-hygiene" "$f:$line — Thread.sleep in test (use runTest + advanceTimeBy): $offending"
  done < <(grep -nE "\bThread\.sleep\b" "$f" || true)

  # 6e — runBlocking without the real-I/O marker.
  # `runTest` drives virtual time: a production withTimeout/delay fires immediately
  # while a real MockWebServer/OkHttp/filesystem callback is still in flight, and the
  # test then fails for a reason unrelated to the code under test. A test that drives
  # real I/O must opt out of virtual time explicitly, one marker per call site, so the
  # exemption stays reviewable instead of becoming a blanket escape hatch.
  while IFS=: read -r line content; do
    [ -z "$line" ] && continue
    case "$content" in
      *//*) continue ;;
      *import*runBlocking*) continue ;;
    esac
    prev_no=$((line - 1))
    prev=""
    [ "$prev_no" -ge 1 ] && prev=$(sed -n "${prev_no}p" "$f")
    printf '%s' "$prev" | grep -qE "//[[:space:]]*{{PREFIX}}-real-io:[[:space:]]*[^[:space:]]" && continue
    offending=$(printf '%s' "$content" | sed 's/^[[:space:]]*//')
    add_v "test-clock" "$f:$line — runBlocking without a '// {{PREFIX}}-real-io: <reason>' marker (use runTest, or justify real time): $offending"
  done < <(grep -nE "\brunBlocking[[:space:]]*[\({]" "$f" || true)
done

# ----- Check 7: module dependency direction ---------------------------
# The expensive semantic reviewer used to be the only thing that could catch a
# module reaching into a module it does not depend on, or a lower layer taking a
# dependency on a higher one. Both are decidable from the gradle files in
# milliseconds, so they belong here. Inert on single-module projects.
SEEN_MODULES=""
for f in "${EXISTING[@]:-}"; do
  [ -n "$f" ] || continue
  m="$(module_of "$f")"
  [ -n "$m" ] || continue
  [ -n "$(gradle_file_of "$m")" ] || continue

  case " $SEEN_MODULES " in
    *" $m "*) ;;
    *)
      SEEN_MODULES="$SEEN_MODULES $m"
      self_rank="$(module_rank "$m")"
      while IFS= read -r d; do
        [ -n "$d" ] || continue
        [ "$d" = "$m" ] && continue
        dep_rank="$(module_rank "$d")"
        if [ "$dep_rank" -gt "$self_rank" ]; then
          add_v "module-direction" "$(gradle_file_of "$m") — :${m//\//:} (layer rank $self_rank) depends on higher layer :${d//\//:} (rank $dep_rank)"
        fi
        if direct_deps "$d" | grep -qx -- "$m"; then
          add_v "module-cycle" "$(gradle_file_of "$m") — module dependency cycle :${m//\//:} <-> :${d//\//:}"
        fi
      done < <(effective_deps "$m" | sort -u)
      ;;
  esac

  # 7c — import from a module this one does not declare. This is the shape of a DI
  # wiring break: it reads fine in review, then fails only at aggregate application
  # build time, or at runtime as a missing binding.
  [ "$(source_set_of "$f")" = main ] || continue
  case "$f" in *.kt) ;; *) continue ;; esac
  eff=" $(effective_deps "$m" | sort -u | tr '\n' ' ') "
  while IFS=: read -r line content; do
    [ -z "$line" ] && continue
    fqn=$(printf '%s' "$content" | sed -e 's/^[[:space:]]*import[[:space:]]*//' -e 's/[[:space:]].*$//' -e 's/\r$//')
    dep_module="$(module_for_import "$fqn")"
    [ -n "$dep_module" ] || continue
    [ "$dep_module" = "$m" ] && continue
    case "$eff" in
      *" $dep_module "*) continue ;;
    esac
    offending=$(printf '%s' "$content" | sed 's/^[[:space:]]*//')
    add_v "module-direction" "$f:$line — imports :${dep_module//\//:}, which :${m//\//:} does not declare as a dependency: $offending"
  done < <(grep -nE "^import ${PACKAGE//./\\.}\." "$f" || true)
done

# ----- Emit JSON --------------------------------------------------------
list_json() {
  local i=0 out='[' e
  for e in "$@"; do
    [ "$i" -gt 0 ] && out="$out,"
    out="$out\"$(json_escape "$e")\""
    i=$((i + 1))
  done
  printf '%s]' "$out"
}

by_check_json() {
  local out='{' i=0 id c seen="" count
  for id in "${CHECK_IDS[@]:-}"; do
    [ -n "$id" ] || continue
    case " $seen " in *" $id "*) continue ;; esac
    seen="$seen $id"
    count=0
    for c in "${CHECK_IDS[@]:-}"; do
      [ "$c" = "$id" ] && count=$((count + 1))
    done
    [ "$i" -gt 0 ] && out="$out,"
    out="$out\"$(json_escape "$id")\":$count"
    i=$((i + 1))
  done
  printf '%s}' "$out"
}

N=0
for v in "${VIOLATIONS[@]:-}"; do [ -n "$v" ] && N=$((N + 1)); done

if [ "$N" -eq 0 ]; then
  printf '{"pass":true,"violations":[],"warnings":[],"by_check":{}}\n'
elif [ "$WARN_ONLY" -eq 1 ]; then
  printf '{"pass":true,"violations":[],"warnings":%s,"by_check":%s}\n' \
    "$(list_json "${VIOLATIONS[@]}")" "$(by_check_json)"
else
  printf '{"pass":false,"violations":%s,"warnings":[],"by_check":%s}\n' \
    "$(list_json "${VIOLATIONS[@]}")" "$(by_check_json)"
fi
