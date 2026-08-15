#!/usr/bin/env bash
# mp-reviewer-android.sh — Clean Architecture layer-boundary checks for the project.
# Emits exactly one JSON line on stdout. No prose, no progress output.
#
# Usage:
#   mp-reviewer-android.sh [--warn-only] <file1> <file2> ...
#   echo -e "file1\nfile2" | mp-reviewer-android.sh [--warn-only]
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


REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf '{"pass":false,"violations":["not a git repo"],"warnings":[],"by_check":{}}\n'
  exit 0
}
cd "$REPO_ROOT"

# package + source root resolved at runtime from the mp-dev project config
CONFIG="$REPO_ROOT/.claude/mp/config.json"
_mpcfg() { grep -oE "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" "$CONFIG" 2>/dev/null | head -1 | sed -E 's/.*:[[:space:]]*"([^"]*)".*/\1/'; }
PACKAGE="$(_mpcfg package)"
SRC_ROOT="app/src/main/java/$(_mpcfg packagePath)"
if [ -z "$PACKAGE" ] || [ -z "$SRC_ROOT" ]; then
  printf '%s\n' '{"pass":false,"violations":["missing or invalid .claude/mp/config.json (need package + packagePath)"],"warnings":[],"by_check":{}}'
  exit 0
fi

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
# These resolvers assign to globals instead of printing. Every `$(...)` call here
# forks a subshell, and they run several times per file per check: on a real
# codebase that turned a millisecond-scale gate into a minutes-scale one, which is
# how a cheap deterministic check stops being run at all.

# resolve_module <path> → R_MOD: gradle module dir ("app", "core/ads"), or "".
R_MOD=""
resolve_module() {
  case "$1" in
    */src/*)                           R_MOD="${1%%/src/*}" ;;
    */build.gradle.kts|*/build.gradle) R_MOD="${1%/*}" ;;
    *)                                 R_MOD="" ;;
  esac
}

# resolve_source_set <path> → R_SET: main | test | androidTest | ""
R_SET=""
resolve_source_set() {
  case "$1" in
    */src/androidTest/*) R_SET='androidTest' ;;
    */src/test/*)        R_SET='test' ;;
    */src/main/*)        R_SET='main' ;;
    *)                   R_SET='' ;;
  esac
}

# resolve_layer <path> → R_LAYER: domain | data | presentation | ""
# A path component named exactly domain/data/presentation/ui wins; otherwise a
# `feature/*` module is presentation by convention. Anything else stays unknown
# and is skipped rather than guessed at — a wrong layer guess produces false
# blockers, which is worse than no check.
R_LAYER=""
resolve_layer() {
  case "/$1/" in
    */domain/*)              R_LAYER='domain';       return ;;
    */data/*)                R_LAYER='data';         return ;;
    */presentation/*|*/ui/*) R_LAYER='presentation'; return ;;
  esac
  resolve_module "$1"
  case "$R_MOD" in
    feature/*|*/feature/*) R_LAYER='presentation'; return ;;
  esac
  R_LAYER=''
}

# resolve_rank <module> → R_RANK: 0 foundation, 1 domain, 2 other library, 3 feature, 4 app.
# A dependency edge from a lower rank to a higher rank inverts the layering.
# Foundation modules (common/util/model/kernel/shared) sit *below* domain: a domain
# module depending on shared primitives is the normal arrangement, and ranking it a
# violation would flag every well-layered project on its first run.
R_RANK=2
resolve_rank() {
  case "$1" in
    app)                                                    R_RANK=4 ;;
    feature/*|*/feature/*)                                  R_RANK=3 ;;
    */domain|domain)                                        R_RANK=1 ;;
    */common|common|*/util|*/utils|*/model|*/kernel|*/shared) R_RANK=0 ;;
    *)                                                      R_RANK=2 ;;
  esac
}

gradle_file_of() {
  if   [ -f "$1/build.gradle.kts" ]; then printf '%s' "$1/build.gradle.kts"
  elif [ -f "$1/build.gradle" ];     then printf '%s' "$1/build.gradle"
  else printf ''; fi
}

# One index of every gradle module in the repo, built once. Import resolution then
# becomes pure-bash membership testing instead of two stat calls per import line.
MODULE_INDEX=" "
while IFS= read -r gf; do
  [ -n "$gf" ] || continue
  d="${gf%/*}"
  case "$MODULE_INDEX" in *" $d "*) continue ;; esac
  MODULE_INDEX="$MODULE_INDEX$d "
done < <(find . -maxdepth 4 \( -name .git -o -name build -o -name node_modules \) -prune -o \
              \( -name 'build.gradle.kts' -o -name 'build.gradle' \) -print 2>/dev/null | sed 's#^\./##')

# gradle_deps <module> <all|api> → newline-separated dependency module dirs.
# Test-only configurations are excluded. `testImplementation(project(":core:testing"))`
# next to that module's own dependency on this one is the standard fakes arrangement,
# not a production cycle, and reporting it as one teaches the reader to ignore the check.
gradle_deps() {
  local gf; gf="$(gradle_file_of "$1")"
  [ -n "$gf" ] || return 0
  awk -v want="$2" '
    match($0, /[A-Za-z]+[( ]*project\(["'"'"'][:][A-Za-z0-9_.:-]+["'"'"']\)/) {
      decl = substr($0, RSTART, RLENGTH)
      cfg = decl; sub(/[( ].*$/, "", cfg)
      if (cfg ~ /^(test|androidTest|debugAndroidTest|kapt|ksp|lintChecks|detektPlugins)/) next
      if (want == "api" && cfg != "api") next
      path = decl; sub(/^[^:]*:/, "", path); sub(/["'"'"']\)$/, "", path)
      gsub(/:/, "/", path)
      if (path != "") print path
    }
  ' "$gf" 2>/dev/null | sort -u
}

direct_deps() { gradle_deps "$1" all; }
api_deps()    { gradle_deps "$1" api; }

# effective_deps <module> → direct deps plus one level of api() re-exports.
effective_deps() {
  local m="$1" d
  direct_deps "$m"
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    api_deps "$d"
  done < <(direct_deps "$m")
}

# resolve_effective_deps <module> → R_EFF: " a/b c/d " for pure-bash membership tests.
# Cached: Check 7c asks the same question once per changed file, and each miss costs
# a gradle-file grep per dependency.
EFF_CACHE=""
R_EFF=" "
resolve_effective_deps() {
  local m="$1" line
  case "$EFF_CACHE" in
    *"|$m="*)
      line="${EFF_CACHE#*"|$m="}"
      R_EFF=" ${line%%|*} "
      return ;;
  esac
  R_EFF=" $(effective_deps "$m" | sort -u | tr '\n' ' ') "
  EFF_CACHE="$EFF_CACHE|$m=$(printf '%s' "$R_EFF" | sed -e 's/^ //' -e 's/ $//')|"
}

# resolve_import_module <import-fqn> → R_IMP: owning module dir, or "".
# Maps <package>.core.ads.data.Foo → core/ads by taking the longest leading segment
# prefix present in MODULE_INDEX. Single-module projects resolve nothing here,
# which correctly makes the module checks inert.
R_IMP=""
resolve_import_module() {
  local rest seg path i
  R_IMP=""
  case "$1" in
    "$PACKAGE".*) rest="${1#"$PACKAGE".}" ;;
    *) return ;;
  esac
  path=""; i=0
  while [ "$i" -lt 3 ]; do
    seg="${rest%%.*}"
    [ "$seg" = "$rest" ] && break
    if [ -n "$path" ]; then path="$path/$seg"; else path="$seg"; fi
    case "$MODULE_INDEX" in *" $path "*) R_IMP="$path" ;; esac
    rest="${rest#*.}"
    i=$((i + 1))
  done
}

# ----- Check 1: no Android imports in domain --------------------------
for f in "${EXISTING[@]:-}"; do
  [ -n "$f" ] || continue
  resolve_layer "$f"; [ "$R_LAYER" = domain ] || continue
  resolve_source_set "$f"; [ "$R_SET" = main ] || continue
  while IFS=: read -r line content; do
    [ -z "$line" ] && continue
    offending="${content#"${content%%[![:space:]]*}"}"
    add_v "domain-purity" "$f:$line — illegal Android import in domain: $offending"
  done < <(grep -nE "^import android\." "$f" || true)
done

# ----- Check 2: no data layer imports in presentation -----------------
# Single-module projects expose the data layer as <package>.data.*; multi-module
# ones expose it as a separate gradle module whose own layer resolves to `data`.
for f in "${EXISTING[@]:-}"; do
  [ -n "$f" ] || continue
  resolve_layer "$f"; [ "$R_LAYER" = presentation ] || continue
  resolve_source_set "$f"; [ "$R_SET" = main ] || continue
  while IFS=: read -r line content; do
    [ -z "$line" ] && continue
    fqn=$(printf '%s' "$content" | sed -e 's/^[[:space:]]*import[[:space:]]*//' -e 's/[[:space:]].*$//' -e 's/\r$//')
    case "$fqn" in
      "$PACKAGE".data.*) ;;
      *)
        resolve_import_module "$fqn"; dep_module="$R_IMP"
        [ -n "$dep_module" ] || continue
        resolve_layer "$dep_module/src/main"; [ "$R_LAYER" = data ] || continue
        ;;
    esac
    offending=$(printf '%s' "$content" | sed 's/^[[:space:]]*//')
    add_v "layer-boundary" "$f:$line — illegal data import in presentation: $offending"
  done < <(grep -nE "^import ${PACKAGE//./\\.}\." "$f" || true)
done

# ----- Check 3: ViewModels must not inject Repository -----------------
for f in "${EXISTING[@]:-}"; do
  [ -n "$f" ] || continue
  resolve_layer "$f"; [ "$R_LAYER" = presentation ] || continue
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
  resolve_layer "$f"; [ "$R_LAYER" = presentation ] || continue
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
  resolve_layer "$f"; [ "$R_LAYER" = presentation ] || continue
  resolve_source_set "$f"; [ "$R_SET" = main ] || continue
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
  resolve_source_set "$f"
  case "$R_SET" in
    test|androidTest) ;;
    *) continue ;;
  esac

  # One pass per file. Each sub-check used to cost its own grep, plus a `sed -n`
  # per match to re-read a line grep had already produced; on a test file with many
  # matches that is hundreds of process spawns for work awk does in a single read.
  while IFS='|' read -r id line offending; do
    [ -n "$id" ] || continue
    case "$id" in
      ignore)   add_v "test-hygiene" "$f:$line — @Ignore without TODO(#issue) reference: $offending" ;;
      noassert) add_v "test-hygiene" "$f:$line — @Test with no assertions in body: $offending" ;;
      trivial)  add_v "test-hygiene" "$f:$line — trivially-true assertion: $offending" ;;
      sleep)    add_v "test-hygiene" "$f:$line — Thread.sleep in test (use runTest + advanceTimeBy): $offending" ;;
      clock)    add_v "test-clock" "$f:$line — runBlocking without a '// mp-real-io: <reason>' marker (use runTest, or justify real time): $offending" ;;
    esac
  done < <(awk '
    { L[NR] = $0 }
    function trim(s) { sub(/^[[:space:]]+/, "", s); return s }
    function emit(id, n) { printf "%s|%d|%s\n", id, n, trim(L[n]) }
    END {
      for (i = 1; i <= NR; i++) {
        line = L[i]
        prev = (i > 1) ? L[i-1] : ""

        # 6a — a disabled test with no issue reference on this or the previous line
        if (line ~ /^[[:space:]]*@Ignore([[:space:]]|\()/ && (line prev) !~ /TODO|#[0-9]+/) emit("ignore", i)

        # 6b — @Test whose body asserts nothing. The body ends at the next JUnit
        # annotation (or 200 lines out): a fixed short window reported healthy long
        # tests — ones with a setup or latch preamble — as assertion-free, and that
        # noise is what makes a gate get ignored.
        if (line ~ /^[[:space:]]*@Test[[:space:]]*$/) {
          stop = i + 200; if (stop > NR) stop = NR
          for (j = i + 1; j <= stop; j++)
            if (L[j] ~ /^[[:space:]]*@(Test|Before|After|BeforeClass|AfterClass|Ignore)([[:space:]]|\(|$)/) { stop = j - 1; break }
          asserted = 0
          for (j = i; j <= stop; j++)
            if (L[j] ~ /assert|expect|verify|should|Truth\./) { asserted = 1; break }
          if (!asserted) emit("noassert", i)
        }

        if (line ~ /\/\//) continue

        # 6c — assertions that cannot fail
        if (line ~ /assertTrue\([[:space:]]*true[[:space:]]*\)|assertFalse\([[:space:]]*false[[:space:]]*\)/) emit("trivial", i)

        # 6d — a blocking sleep instead of a controlled clock
        if (line ~ /Thread\.sleep/) emit("sleep", i)

        # 6e — runBlocking without the real-I/O marker. runTest drives virtual time:
        # a production withTimeout/delay fires immediately while a real
        # MockWebServer/OkHttp/filesystem callback is still in flight, and the test
        # then fails for a reason unrelated to the code under test. Opting out must
        # stay explicit, one call site at a time, so it remains reviewable instead of
        # becoming a blanket escape hatch.
        if (line ~ /runBlocking[[:space:]]*[({]/ && line !~ /^[[:space:]]*import[[:space:]]/ &&
            prev !~ /\/\/[[:space:]]*mp-real-io:[[:space:]]*[^[:space:]]/) emit("clock", i)
      }
    }
  ' "$f")
done

# ----- Check 7: module dependency direction ---------------------------
# The expensive semantic reviewer used to be the only thing that could catch a
# module reaching into a module it does not depend on, or a lower layer taking a
# dependency on a higher one. Both are decidable from the gradle files in
# milliseconds, so they belong here. Inert on single-module projects.
SEEN_MODULES=""
for f in "${EXISTING[@]:-}"; do
  [ -n "$f" ] || continue
  resolve_module "$f"; m="$R_MOD"
  [ -n "$m" ] || continue
  [ -n "$(gradle_file_of "$m")" ] || continue

  case " $SEEN_MODULES " in
    *" $m "*) ;;
    *)
      SEEN_MODULES="$SEEN_MODULES $m"
      resolve_rank "$m"; self_rank="$R_RANK"
      while IFS= read -r d; do
        [ -n "$d" ] || continue
        [ "$d" = "$m" ] && continue
        resolve_rank "$d"; dep_rank="$R_RANK"
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
  resolve_source_set "$f"; [ "$R_SET" = main ] || continue
  case "$f" in *.kt) ;; *) continue ;; esac
  resolve_effective_deps "$m"; eff="$R_EFF"
  while IFS=: read -r line content; do
    [ -z "$line" ] && continue
    fqn=$(printf '%s' "$content" | sed -e 's/^[[:space:]]*import[[:space:]]*//' -e 's/[[:space:]].*$//' -e 's/\r$//')
    resolve_import_module "$fqn"; dep_module="$R_IMP"
    [ -n "$dep_module" ] || continue
    [ "$dep_module" = "$m" ] && continue
    case "$eff" in
      *" $dep_module "*) continue ;;
    esac
    offending=$(printf '%s' "$content" | sed 's/^[[:space:]]*//')
    add_v "module-direction" "$f:$line — imports :${dep_module//\//:}, which :${m//\//:} does not declare as a dependency: $offending"
  done < <(grep -nE "^import ${PACKAGE//./\\.}\." "$f" || true)
done

# ----- Check 8: a touched use case needs a dedicated test -------------
# The full verifier already rejects a new use case that has no test of its own,
# but it runs at the very end: on a measured run that rejection arrived after the
# implementation, the review cycles and a full test suite had all completed, and
# it cost another repair pass plus a full re-verify. The same fact is decidable
# here from a filename, in milliseconds, before any of that is spent.
UC_FILES=()
UC_NAMES=()
for f in "${EXISTING[@]:-}"; do
  [ -n "$f" ] || continue
  case "$f" in *.kt) ;; *) continue ;; esac
  resolve_source_set "$f"; [ "$R_SET" = main ] || continue
  base="${f##*/}"; base="${base%.kt}"
  is_uc=0
  case "$f" in */usecase/*|*/usecases/*) is_uc=1 ;; esac
  case "$base" in *UseCase) is_uc=1 ;; esac
  [ "$is_uc" -eq 1 ] || continue
  # An interface-only or typealias file has nothing of its own to test.
  grep -qE '^[[:space:]]*(class|object)[[:space:]]' "$f" 2>/dev/null || continue
  UC_FILES+=("$f")
  UC_NAMES+=("$base")
done

if [ "${#UC_FILES[@]}" -gt 0 ]; then
  TEST_INDEX=$(find . \( -name .git -o -name build -o -name .claude -o -name archive -o -name node_modules \) -prune -o \
                 -path '*/src/test*' -name '*Test.kt' -print 2>/dev/null | sed 's#.*/##')
  i=0
  while [ "$i" -lt "${#UC_FILES[@]}" ]; do
    f="${UC_FILES[$i]}"; base="${UC_NAMES[$i]}"
    i=$((i + 1))
    printf '%s\n' "$TEST_INDEX" | grep -qx "${base}Test.kt" && continue
    add_v "usecase-test" "$f — use case $base has no dedicated ${base}Test.kt; the full verifier rejects this at the end of the run, after the tests and reviews have already been paid for"
  done
fi

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
