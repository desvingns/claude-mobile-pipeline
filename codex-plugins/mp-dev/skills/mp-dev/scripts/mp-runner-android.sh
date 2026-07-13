#!/usr/bin/env bash
# mp-runner-android.sh — Gradle verification for the project.
# Emits exactly one JSON line on stdout. All gradle/grep noise goes to temp files.
#
# Usage: mp-runner-android.sh [screenshot_record_needed] [target_coverage_pct]
#   screenshot_record_needed: "true" | "false" (default: "false")
#   target_coverage_pct:      integer 0-100, line-coverage minimum (default: 65)
#                             pass 0 to disable the coverage gate entirely
#
# Output (success):
#   {"pass":true,"tests":"42 passed / 0 failed","detekt":"ok","lint":"ok","coverage":"67%","screenshots":"ok|skipped"}
# Output (failure):
#   {"pass":false,"tests":"40 passed / 2 failed","detekt":"3 violations","lint":"ok","coverage":"57% (below 65% threshold)","screenshots":"skipped","errors":["..."]}

set -uo pipefail

SCREENSHOT_NEEDED="${1:-false}"
TARGET_COVERAGE="${2:-65}"

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
  printf '{"pass":false,"tests":"unknown","detekt":"unknown","screenshots":"skipped","errors":["not a git repo"]}\n'
  exit 0
}
cd "$REPO_ROOT"

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

# ----- Step 1: unit tests -----------------------------------------------
TEST_LOG="$LOG_DIR/tests.log"
./gradlew :app:testDebugUnitTest --no-daemon >"$TEST_LOG" 2>&1
TEST_EXIT=$?

SUMMARY_LINE=$(grep -E "[0-9]+ tests? completed" "$TEST_LOG" | tail -n 1 || true)
if [ -n "$SUMMARY_LINE" ]; then
  TOTAL=$(printf '%s' "$SUMMARY_LINE" | grep -oE '^[0-9]+ tests? completed' | grep -oE '^[0-9]+')
  FAILED=$(printf '%s' "$SUMMARY_LINE" | grep -oE '[0-9]+ failed' | grep -oE '^[0-9]+' || echo 0)
  TOTAL="${TOTAL:-0}"
  FAILED="${FAILED:-0}"
  PASSED=$((TOTAL - FAILED))
  TESTS_RESULT="${PASSED} passed / ${FAILED} failed"
else
  TESTS_RESULT="no test summary"
  FAILED=1
  FAIL_LINE=$(grep -E "BUILD FAILED|FAILURE: |error:" "$TEST_LOG" | head -n 3 || true)
  if [ -n "$FAIL_LINE" ]; then
    while IFS= read -r line; do
      [ -n "$line" ] && add_err "$line"
    done <<<"$FAIL_LINE"
  else
    add_err "gradle exit=$TEST_EXIT, no parseable output"
  fi
fi

if [ "$FAILED" -gt 0 ]; then
  while IFS= read -r line; do
    [ -n "$line" ] && add_err "$line"
  done < <(grep -E " FAILED$" "$TEST_LOG" | head -n 5 || true)
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

# ----- Step 4: JaCoCo coverage threshold --------------------------------
COVERAGE_RESULT="skipped"
if [ "$TARGET_COVERAGE" -gt 0 ]; then
  COV_LOG="$LOG_DIR/jacoco.log"
  ./gradlew :app:jacocoUnitTestReport --no-daemon >"$COV_LOG" 2>&1
  COV_EXIT=$?

  COV_XML="app/build/reports/jacoco/jacocoUnitTestReport/jacocoUnitTestReport.xml"
  if [ "$COV_EXIT" -eq 0 ] && [ -f "$COV_XML" ]; then
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
    add_err "jacoco report missing (exit=$COV_EXIT)"
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
  skipped|[0-9]*%) ;;
  *) PASS=false ;;
esac
case "$SCREENSHOTS_RESULT" in
  ok|skipped) ;;
  *) PASS=false ;;
esac

# ----- Emit JSON (only stdout output of this script) --------------------
if [ "$PASS" = "true" ]; then
  printf '{"pass":true,"tests":"%s","detekt":"%s","lint":"%s","coverage":"%s","screenshots":"%s"}\n' \
    "$(json_escape "$TESTS_RESULT")" \
    "$(json_escape "$DETEKT_RESULT")" \
    "$(json_escape "$LINT_RESULT")" \
    "$(json_escape "$COVERAGE_RESULT")" \
    "$(json_escape "$SCREENSHOTS_RESULT")"
else
  printf '{"pass":false,"tests":"%s","detekt":"%s","lint":"%s","coverage":"%s","screenshots":"%s","errors":%s}\n' \
    "$(json_escape "$TESTS_RESULT")" \
    "$(json_escape "$DETEKT_RESULT")" \
    "$(json_escape "$LINT_RESULT")" \
    "$(json_escape "$COVERAGE_RESULT")" \
    "$(json_escape "$SCREENSHOTS_RESULT")" \
    "$(errors_json)"
fi
