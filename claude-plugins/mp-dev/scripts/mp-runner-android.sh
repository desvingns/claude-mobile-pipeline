#!/usr/bin/env bash
# mp-runner-android.sh — Gradle verification for the project.
# Emits exactly one JSON line on stdout. All gradle/grep noise goes to temp files.
#
# Usage: mp-runner-android.sh [screenshot_record_needed] [target_coverage_pct]
#        mp-runner-android.sh --scope "<module> [<module>...]"
#   screenshot_record_needed: "true" | "false" (default: "false")
#   target_coverage_pct:      integer 0-100, line-coverage minimum (default: 65)
#                             pass 0 to disable the coverage gate entirely
#   --scope:                  run unit tests for the listed gradle modules only
#                             (":core:ads" or "core/ads" both accepted) and skip
#                             detekt, lint, coverage, and screenshots. The test
#                             task is resolved per module (Android →
#                             testDebugUnitTest, pure JVM → test); a module that
#                             cannot be located, or a task that does not exist,
#                             is reported as "error_kind":"task_not_found" and
#                             never as a code failure.
#
# Scoped mode exists for the inner loop. A repair cycle that re-runs the whole
# multi-module suite plus lint plus coverage to learn whether six tests in one
# module now pass is paying a release-gate price for a debugging question. The
# full run stays mandatory once, as the final gate before the verifier — a scoped
# run cannot see a break in a module it did not touch.
#
# Output (success):
#   {"pass":true,"mode":"full","tests":"42 passed / 0 failed","detekt":"ok","lint":"ok","coverage":"67%","screenshots":"ok|skipped"}
# Output (scoped):
#   {"pass":true,"mode":"scoped","scope":":core:ads","tests":"12 passed / 0 failed / 0 skipped","detekt":"skipped","lint":"skipped","coverage":"skipped","screenshots":"skipped"}
# Output (failure):
#   {"pass":false,"mode":"full","tests":"40 passed / 2 failed","detekt":"3 violations","lint":"ok","coverage":"57% (below 65% threshold)","screenshots":"skipped","errors":["..."]}

set -uo pipefail

SCOPE_MODULES=""
SCOPE_GIVEN=0
SCREENSHOT_NEEDED="false"
TARGET_COVERAGE_ARG=""
POSITIONAL=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --scope)
      SCOPE_GIVEN=1
      SCOPE_MODULES="${2:-}"
      shift 2 || shift
      ;;
    *)
      POSITIONAL=$((POSITIONAL + 1))
      if [ "$POSITIONAL" -eq 1 ]; then SCREENSHOT_NEEDED="$1"; else TARGET_COVERAGE_ARG="$1"; fi
      shift
      ;;
  esac
done

MODE=full
if [ "$SCOPE_GIVEN" -eq 1 ]; then
  MODE=scoped
  SCREENSHOT_NEEDED=false
  TARGET_COVERAGE_ARG=0
  # An empty --scope must fail loudly. Falling back to a full run would hand the
  # caller a release-gate result while it believes it asked for an inner-loop one.
  if [ -z "$(printf '%s' "$SCOPE_MODULES" | tr -d '[:space:]')" ]; then
    printf '{"pass":false,"mode":"scoped","scope":"","tests":"unknown","detekt":"skipped","lint":"skipped","coverage":"skipped","screenshots":"skipped","errors":["--scope requires at least one module"]}\n'
    exit 0
  fi
fi

# ----- JBR detection (cross-platform; first match wins) ------------------
for candidate in \
    "$HOME"/.jbr/jbr_jcef-17* \
    /snap/android-studio/current/jbr \
    /opt/android-studio/jbr \
    /Applications/Android\ Studio.app/Contents/jbr/Contents/Home \
    "/c/Program Files/Android/Android Studio/jbr" \
    "${LOCALAPPDATA:-}/Programs/Android Studio/jbr"; do
  if [ -x "$candidate/bin/java" ] || [ -x "$candidate/bin/java.exe" ]; then
    export JAVA_HOME="$candidate"
    export PATH="$JAVA_HOME/bin:$PATH"
    break
  fi
done

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf '{"pass":false,"mode":"%s","tests":"unknown","detekt":"unknown","screenshots":"skipped","errors":["not a git repo"]}\n' "$MODE"
  exit 0
}
cd "$REPO_ROOT"

# Threshold precedence: explicit arg > .claude/mp/config.json coverageTargetPct > 65.
# Resolved after cd so the config path is repo-relative. A project with its own
# per-module coverage gate (kover koverLineFloors, jacoco rules) sets 0 here so this
# flat bar cannot contradict the gate it already trusts.
TARGET_COVERAGE="$TARGET_COVERAGE_ARG"
if [ -z "$TARGET_COVERAGE" ]; then
  TARGET_COVERAGE=$(grep -o '"coverageTargetPct"[[:space:]]*:[[:space:]]*[0-9]\{1,3\}' \
                    .claude/mp/config.json 2>/dev/null | grep -o '[0-9]\{1,3\}$' | head -n 1)
fi
case "${TARGET_COVERAGE:-}" in ''|*[!0-9]*) TARGET_COVERAGE=65 ;; esac

LOG_DIR=$(mktemp -d)
trap 'rm -rf "$LOG_DIR"' EXIT

ERRORS=()
add_err() { ERRORS+=("$1"); }

# ----- JSON helpers (no jq dependency) ----------------------------------
json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

errors_json() {
  if [ "${#ERRORS[@]}" -eq 0 ]; then
    printf '[]'
    return
  fi
  local i=0 out='['
  for e in "${ERRORS[@]}"; do
    [ "$i" -gt 0 ] && out+=','
    out+="\"$(json_escape "$e")\""
    i=$((i + 1))
  done
  out+=']'
  printf '%s' "$out"
}

# ----- Scope resolution: the test task is per module, not per project -----
# An Android application/library module answers to testDebugUnitTest; a plain
# JVM/Kotlin module only to test. Addressing a pure JVM module as
# `:core:domain:testDebugUnitTest` makes Gradle fail *configuration*, which this
# script then reported as "compile/config failure" — a healthy module looked
# broken and cost a diagnosis cycle before anyone noticed the task never existed.
# A module we cannot locate at all is reported as task_not_found, which is a
# different fact from "the tests failed" and must not be conflated with it.
module_test_task() {
  local dir="$1" bf
  for bf in "$dir/build.gradle.kts" "$dir/build.gradle"; do
    [ -f "$bf" ] || continue
    if grep -qE '^[[:space:]]*android[[:space:]]*\{|com\.android\.(application|library)|plugins\.android\.(application|library)' "$bf" 2>/dev/null; then
      printf 'testDebugUnitTest'; return 0
    fi
    # A convention plugin can apply the Android plugin without the consumer ever
    # opening an `android {}` block; the manifest is the reliable second signal.
    if [ -f "$dir/src/main/AndroidManifest.xml" ]; then
      printf 'testDebugUnitTest'; return 0
    fi
    printf 'test'; return 0
  done
  return 1
}

SCOPE_PAIRS=""
SCOPE_LABEL=""
if [ "$MODE" = scoped ]; then
  MISSING=""
  for mod in $SCOPE_MODULES; do
    mod="${mod#:}"
    dir="${mod//://}"
    path=":${dir//\//:}"
    if [ -n "${MP_TEST_TASK:-}" ]; then
      task="$MP_TEST_TASK"
    elif ! task="$(module_test_task "$dir")"; then
      MISSING="$MISSING $path"
      continue
    fi
    SCOPE_PAIRS="$SCOPE_PAIRS $dir=$task"
    [ -n "$SCOPE_LABEL" ] && SCOPE_LABEL="$SCOPE_LABEL "
    SCOPE_LABEL="$SCOPE_LABEL$path"
  done
  SCOPE_PAIRS="${SCOPE_PAIRS# }"
  if [ -n "$MISSING" ]; then
    printf '{"pass":false,"mode":"scoped","scope":"%s","tests":"unknown","detekt":"skipped","lint":"skipped","coverage":"skipped","screenshots":"skipped","error_kind":"task_not_found","errors":["no gradle build file for module(s):%s"]}\n' \
      "$(json_escape "$SCOPE_LABEL")" "$(json_escape "$MISSING")"
    exit 0
  fi
fi

# ----- Step 1: unit tests -----------------------------------------------
# Default to the multi-module task: a `:app`-only run leaves a compile break in
# other modules invisible and reports green. Override with MP_TEST_TASK.
TEST_LOG="$LOG_DIR/tests.log"
TEST_TASK="${MP_TEST_TASK:-testDebugUnitTest}"
if [ "$MODE" = scoped ]; then
  TEST_TASK=""
  for pair in $SCOPE_PAIRS; do
    dir="${pair%%=*}"; task="${pair##*=}"
    TEST_TASK="$TEST_TASK :${dir//\//:}:$task"
  done
  TEST_TASK="${TEST_TASK# }"
fi
# Results dir is named after the bare task, so a debug run never counts stale
# testReleaseUnitTest XML (different variant, different numbers) as its own.
# In scoped mode each module carries its own task, so the dir is resolved per
# module below instead of from a single shared task name.
RESULT_DIR="${TEST_TASK##* }"
RESULT_DIR="${RESULT_DIR##*:}"
# shellcheck disable=SC2086
./gradlew $TEST_TASK --no-daemon --continue >"$TEST_LOG" 2>&1
TEST_EXIT=$?

# JUnit XML is the source of truth for pass/fail counts. Gradle emits its
# "N tests completed, M failed" line only inside AbstractTestTask's FAILURE
# message — a fully green run never prints it at all — so grepping stdout made
# this gate fail hard on every healthy run.
TOTAL=0; FAILED=0; SKIPPED=0; SUITES=0
while IFS= read -r xml; do
  [ -n "$xml" ] || continue
  attrs=$(tr '\n' ' ' <"$xml" | grep -o '<testsuite [^>]*>' | head -n 1)
  [ -n "$attrs" ] || continue
  t=$(printf '%s' "$attrs" | grep -o 'tests="[0-9]*"'    | grep -o '[0-9]*' | head -n 1)
  f=$(printf '%s' "$attrs" | grep -o 'failures="[0-9]*"' | grep -o '[0-9]*' | head -n 1)
  e=$(printf '%s' "$attrs" | grep -o 'errors="[0-9]*"'   | grep -o '[0-9]*' | head -n 1)
  s=$(printf '%s' "$attrs" | grep -o 'skipped="[0-9]*"'  | grep -o '[0-9]*' | head -n 1)
  TOTAL=$((TOTAL + ${t:-0}))
  FAILED=$((FAILED + ${f:-0} + ${e:-0}))
  SKIPPED=$((SKIPPED + ${s:-0}))
  SUITES=$((SUITES + 1))
done < <(
  if [ "$MODE" = scoped ]; then
    # Only the scoped modules' reports. A repo-wide sweep would pick up XML left
    # behind by an earlier full run and report the whole suite's numbers as this
    # run's result — a scoped gate that silently claims full coverage is worse
    # than no scoped gate at all.
    for pair in $SCOPE_PAIRS; do
      dir="${pair%%=*}"; task="${pair##*=}"
      [ -d "$dir/build/test-results/$task" ] || continue
      find "$dir/build/test-results/$task" -name 'TEST-*.xml' -print 2>/dev/null
    done
  else
    find . \( -name .git -o -name .claude -o -name archive -o -name node_modules \) -prune -o \
         -path "*/build/test-results/$RESULT_DIR/*" -name 'TEST-*.xml' -print 2>/dev/null
  fi
)

# Classify the failure BEFORE any bookkeeping sets FAILED, so the carve-out below
# still applies in the case it exists for: a task that does not exist produces no
# test suites at all, which is also what "the build died early" looks like.
ERROR_KIND=""
if [ "$TEST_EXIT" -ne 0 ] &&
   grep -qE "Task '[^']*' not found|Cannot locate tasks that match" "$TEST_LOG" 2>/dev/null; then
  ERROR_KIND="task_not_found"
fi

PASSED=$((TOTAL - FAILED - SKIPPED))
if [ "$SUITES" -eq 0 ]; then
  if [ "$TEST_EXIT" -eq 0 ]; then
    TESTS_RESULT="0 tests (no test sources matched $TEST_TASK)"
  elif [ "$ERROR_KIND" = task_not_found ]; then
    TESTS_RESULT="no tests ran — the requested task does not exist for this module"
    FAILED=1
  else
    TESTS_RESULT="build failed before any test ran"
    FAILED=1
  fi
else
  TESTS_RESULT="${PASSED} passed / ${FAILED} failed / ${SKIPPED} skipped"
fi

# Non-zero Gradle exit with a clean XML set means compile/config breakage, not an
# assertion failure — the usual way a broken module hides behind green test reports.
# "Task not found" (classified above) is carved out of that bucket: it means we
# addressed a module with a task it does not have, which says nothing about the
# code and must not be handed to a developer as a compile error to chase.
if [ "$TEST_EXIT" -ne 0 ] && [ "$FAILED" -eq 0 ]; then
  if [ "$ERROR_KIND" = task_not_found ]; then
    TESTS_RESULT="$TESTS_RESULT (gradle exit=$TEST_EXIT — requested task does not exist for this module)"
  else
    TESTS_RESULT="$TESTS_RESULT (gradle exit=$TEST_EXIT — compile/config failure)"
  fi
  FAILED=1
fi

if [ "$FAILED" -gt 0 ]; then
  while IFS= read -r line; do
    [ -n "$line" ] && add_err "$line"
  done < <(grep -E "BUILD FAILED|FAILURE: |^e: |error:| FAILED$" "$TEST_LOG" | head -n 5 || true)
fi

# ----- Scoped mode stops here --------------------------------------------
# Static analysis and coverage are release-gate concerns, not inner-loop ones.
if [ "$MODE" = scoped ]; then
  if [ "$FAILED" -gt 0 ]; then
    KIND_FIELD=""
    [ -n "$ERROR_KIND" ] && KIND_FIELD="\"error_kind\":\"$ERROR_KIND\","
    printf '{"pass":false,"mode":"scoped","scope":"%s","tests":"%s","detekt":"skipped","lint":"skipped","coverage":"skipped","screenshots":"skipped",%s"errors":%s}\n' \
      "$(json_escape "$SCOPE_LABEL")" "$(json_escape "$TESTS_RESULT")" "$KIND_FIELD" "$(errors_json)"
  else
    printf '{"pass":true,"mode":"scoped","scope":"%s","tests":"%s","detekt":"skipped","lint":"skipped","coverage":"skipped","screenshots":"skipped"}\n' \
      "$(json_escape "$SCOPE_LABEL")" "$(json_escape "$TESTS_RESULT")"
  fi
  exit 0
fi

# ----- Step 2: detekt ----------------------------------------------------
DETEKT_LOG="$LOG_DIR/detekt.log"
./gradlew :app:detekt --no-daemon >"$DETEKT_LOG" 2>&1
DETEKT_EXIT=$?

ISSUES_LINE=$(grep -E "[0-9]+ issues? found" "$DETEKT_LOG" | tail -n 1 || true)
if [ -n "$ISSUES_LINE" ]; then
  ISSUES=$(printf '%s' "$ISSUES_LINE" | grep -oE '^[0-9]+' || echo 0)
  ISSUES="${ISSUES:-0}"
  if [ "$ISSUES" -eq 0 ]; then
    DETEKT_RESULT="ok"
  else
    DETEKT_RESULT="${ISSUES} violations"
    while IFS= read -r line; do
      [ -n "$line" ] && add_err "$line"
    done < <(grep -E "\.kt:[0-9]+:" "$DETEKT_LOG" | head -n 10 || true)
  fi
elif [ "$DETEKT_EXIT" -eq 0 ]; then
  DETEKT_RESULT="ok"
else
  DETEKT_RESULT="failed"
  add_err "detekt exit=$DETEKT_EXIT"
fi

# ----- Step 3: Android Lint ---------------------------------------------
LINT_LOG="$LOG_DIR/lint.log"
./gradlew :app:lintDebug --no-daemon >"$LINT_LOG" 2>&1
LINT_EXIT=$?

# Lint summary line is typically "N errors, M warnings"
LINT_SUMMARY=$(grep -oE "[0-9]+ errors?, [0-9]+ warnings?" "$LINT_LOG" | tail -n 1 || true)
if [ -n "$LINT_SUMMARY" ]; then
  LINT_ERRORS=$(printf '%s' "$LINT_SUMMARY" | grep -oE '^[0-9]+')
  if [ "${LINT_ERRORS:-1}" -eq 0 ]; then
    LINT_RESULT="ok"
  else
    LINT_RESULT="${LINT_ERRORS} errors"
    while IFS= read -r line; do
      [ -n "$line" ] && add_err "$line"
    done < <(grep -E "^(Error|error:|src/main/.*: Error)" "$LINT_LOG" | head -n 5 || true)
  fi
elif [ "$LINT_EXIT" -eq 0 ]; then
  LINT_RESULT="ok"
else
  LINT_RESULT="failed"
  add_err "lint exit=$LINT_EXIT, no parseable summary"
fi

# ----- Step 4: coverage threshold ---------------------------------------
# Tool is auto-detected: hard-coding the JaCoCo task made every run of a
# kover-based project fail a step it could never satisfy, dragging pass to false
# regardless of code health. Kover emits JaCoCo-format XML, so one parser serves both.
COVERAGE_RESULT="skipped"
if [ "$TARGET_COVERAGE" -gt 0 ]; then
  COV_LOG="$LOG_DIR/coverage.log"
  COV_TASK="${MP_COVERAGE_TASK:-}"
  if [ -z "$COV_TASK" ]; then
    BUILD_FILES="build.gradle build.gradle.kts app/build.gradle app/build.gradle.kts gradle/libs.versions.toml"
    # shellcheck disable=SC2086
    if grep -qsli 'jacoco' $BUILD_FILES 2>/dev/null; then
      COV_TASK=":app:jacocoUnitTestReport"
    elif grep -qsli 'kover' $BUILD_FILES 2>/dev/null; then
      COV_TASK="koverXmlReport"
    fi
  fi
fi

if [ "$TARGET_COVERAGE" -gt 0 ] && [ -z "$COV_TASK" ]; then
  # No coverage plugin configured. A project fact, not a verification failure —
  # it must never drag the verdict to false.
  COVERAGE_RESULT="n/a (no coverage plugin detected)"
elif [ "$TARGET_COVERAGE" -gt 0 ]; then
  # shellcheck disable=SC2086
  ./gradlew $COV_TASK --no-daemon >"$COV_LOG" 2>&1
  COV_EXIT=$?

  COV_XML=""
  for cand in \
      "app/build/reports/jacoco/jacocoUnitTestReport/jacocoUnitTestReport.xml" \
      "build/reports/kover/report.xml" \
      "app/build/reports/kover/report.xml"; do
    if [ -f "$cand" ]; then COV_XML="$cand"; break; fi
  done

  if [ "$COV_EXIT" -eq 0 ] && [ -n "$COV_XML" ] && [ -f "$COV_XML" ]; then
    # The LAST <counter type="LINE" .../> in the report is the project-wide total.
    COV_PCT=$(grep -oE '<counter type="LINE" missed="[0-9]+" covered="[0-9]+"/>' "$COV_XML" |
              tail -n 1 |
              awk -F'"' '{m=$4; c=$6; t=m+c; if (t>0) printf "%.0f", c*100/t; else printf "0"}')
    COV_PCT="${COV_PCT:-0}"
    if [ "$COV_PCT" -lt "$TARGET_COVERAGE" ]; then
      COVERAGE_RESULT="${COV_PCT}% (below ${TARGET_COVERAGE}% threshold)"
      add_err "coverage ${COV_PCT}% below threshold ${TARGET_COVERAGE}%"
    else
      COVERAGE_RESULT="${COV_PCT}%"
    fi
  else
    COVERAGE_RESULT="unknown"
    add_err "coverage report missing for task $COV_TASK (exit=$COV_EXIT)"
  fi
fi

# ----- Step 5: screenshots (only if requested) --------------------------
if [ "$SCREENSHOT_NEEDED" = "true" ]; then
  REC_LOG="$LOG_DIR/record.log"
  VER_LOG="$LOG_DIR/verify.log"
  ./gradlew :app:recordRoborazziDebug --no-daemon >"$REC_LOG" 2>&1
  REC_EXIT=$?
  ./gradlew :app:verifyRoborazziDebug --no-daemon >"$VER_LOG" 2>&1
  VER_EXIT=$?
  if [ "$REC_EXIT" -eq 0 ] && [ "$VER_EXIT" -eq 0 ]; then
    SCREENSHOTS_RESULT="ok"
  else
    FAILS=$(grep -cE "FAILED" "$VER_LOG" 2>/dev/null || echo 0)
    SCREENSHOTS_RESULT="${FAILS:-?} failures"
    while IFS= read -r line; do
      [ -n "$line" ] && add_err "$line"
    done < <(grep -E "FAILED|error" "$VER_LOG" | head -n 5 || true)
  fi
else
  SCREENSHOTS_RESULT="skipped"
fi

# ----- Verdict ----------------------------------------------------------
PASS=true
[ "$FAILED" -gt 0 ] && PASS=false
[ "$DETEKT_RESULT" != "ok" ] && PASS=false
[ "$LINT_RESULT" != "ok" ] && PASS=false
case "$COVERAGE_RESULT" in
  skipped|n/a*|[0-9]*%) ;;
  *) PASS=false ;;
esac
case "$SCREENSHOTS_RESULT" in
  ok|skipped) ;;
  *) PASS=false ;;
esac

# ----- Emit JSON (only stdout output of this script) --------------------
if [ "$PASS" = "true" ]; then
  printf '{"pass":true,"mode":"full","tests":"%s","detekt":"%s","lint":"%s","coverage":"%s","screenshots":"%s"}\n' \
    "$(json_escape "$TESTS_RESULT")" \
    "$(json_escape "$DETEKT_RESULT")" \
    "$(json_escape "$LINT_RESULT")" \
    "$(json_escape "$COVERAGE_RESULT")" \
    "$(json_escape "$SCREENSHOTS_RESULT")"
else
  printf '{"pass":false,"mode":"full","tests":"%s","detekt":"%s","lint":"%s","coverage":"%s","screenshots":"%s","errors":%s}\n' \
    "$(json_escape "$TESTS_RESULT")" \
    "$(json_escape "$DETEKT_RESULT")" \
    "$(json_escape "$LINT_RESULT")" \
    "$(json_escape "$COVERAGE_RESULT")" \
    "$(json_escape "$SCREENSHOTS_RESULT")" \
    "$(errors_json)"
fi
