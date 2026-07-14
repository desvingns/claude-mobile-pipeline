#!/usr/bin/env bash
# mp-reviewer-android.sh — Clean Architecture layer-boundary checks for the project.
# Emits exactly one JSON line on stdout. No prose, no progress output.
#
# Usage:
#   mp-reviewer-android.sh <file1> <file2> ...
#   echo -e "file1\nfile2" | mp-reviewer-android.sh
#
# Paths in CHANGED_FILES are relative to repo root. Pre-existing violations in
# files NOT listed are ignored, per the agent contract.
#
# Output (clear):    {"pass":true,"violations":[]}
# Output (failure):  {"pass":false,"violations":["<path>:<line> — <msg>", ...]}

set -uo pipefail


REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf '{"pass":false,"violations":["not a git repo"]}\n'
  exit 0
}
cd "$REPO_ROOT"

# package + source root resolved at runtime from the mp-dev project config
CONFIG="$REPO_ROOT/.claude/mp/config.json"
_mpcfg() { grep -oE "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" "$CONFIG" 2>/dev/null | head -1 | sed -E 's/.*:[[:space:]]*"([^"]*)".*/\1/'; }
PACKAGE="$(_mpcfg package)"
SRC_ROOT="app/src/main/java/$(_mpcfg packagePath)"
if [ -z "$PACKAGE" ] || [ -z "$SRC_ROOT" ]; then
  printf '%s\n' '{"pass":false,"violations":["missing or invalid .claude/mp/config.json (need package + packagePath)"]}'
  exit 0
fi

# ----- collect CHANGED_FILES from args, or stdin if no args -------------
CHANGED=()
if [ "$#" -gt 0 ]; then
  for f in "$@"; do
    [ -n "$f" ] && CHANGED+=("$f")
  done
else
  if [ -p /dev/stdin ]; then
    while IFS= read -r line; do
      [ -n "$line" ] && CHANGED+=("$line")
    done
  fi
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
add_v() { VIOLATIONS+=("$1"); }

# ----- Filter CHANGED to existing files only ----------------------------
EXISTING=()
for f in "${CHANGED[@]:-}"; do
  [ -f "$f" ] && EXISTING+=("$f")
done

under() {
  case "$1" in
    "$2"*) return 0 ;;
    *)     return 1 ;;
  esac
}

# ----- Check 1: no Android imports in domain --------------------------
for f in "${EXISTING[@]:-}"; do
  under "$f" "$SRC_ROOT/domain/" || continue
  while IFS=: read -r line _; do
    [ -z "$line" ] && continue
    offending=$(sed -n "${line}p" "$f" | sed 's/^[[:space:]]*//')
    add_v "$f:$line — illegal Android import in domain: $offending"
  done < <(grep -nE "^import android\." "$f" || true)
done

# ----- Check 2: no data layer imports in presentation -----------------
for f in "${EXISTING[@]:-}"; do
  under "$f" "$SRC_ROOT/presentation/" || continue
  while IFS=: read -r line _; do
    [ -z "$line" ] && continue
    offending=$(sed -n "${line}p" "$f" | sed 's/^[[:space:]]*//')
    add_v "$f:$line — illegal data import in presentation: $offending"
  done < <(grep -nE "^import ${PACKAGE//./\\.}\.data\." "$f" || true)
done

# ----- Check 3: ViewModels must not inject Repository -----------------
for f in "${EXISTING[@]:-}"; do
  under "$f" "$SRC_ROOT/presentation/" || continue
  case "$(basename "$f")" in
    *ViewModel.kt) ;;
    *) continue ;;
  esac
  while IFS=: read -r line content; do
    [ -z "$line" ] && continue
    case "$content" in
      *import\ *|*//*|*\*\ *) continue ;;
    esac
    offending=$(printf '%s' "$content" | sed 's/^[[:space:]]*//')
    add_v "$f:$line — ViewModel injects Repository directly (must go via UseCase): $offending"
  done < <(grep -nE ":\s*[A-Z][A-Za-z0-9_]*Repository\b" "$f" || true)
done

# ----- Check 4: Screen composables expose <Name>Content() -------------
for f in "${EXISTING[@]:-}"; do
  under "$f" "$SRC_ROOT/presentation/" || continue
  base=$(basename "$f")
  case "$base" in
    *Screen.kt) ;;
    *) continue ;;
  esac
  if ! grep -qE "^[[:space:]]*(public[[:space:]]+)?fun[[:space:]]+[A-Z][A-Za-z0-9_]*Content[[:space:]]*\(" "$f"; then
    add_v "$f — missing public <Name>Content(...) composable; Screen wrappers must expose a testable Content body"
  fi
done

# ----- Check 5: no hardcoded UI values in presentation/ ---------------
# Tokens belong in ui/theme/ (Color.kt, Type.kt, Spacing.kt, Motion.kt). In screen
# code, reference via MaterialTheme.colorScheme.X, MaterialTheme.typography.X,
# LocalSpacing.current.X, LocalMotion.current.X.
# Allowlist for raw .dp: 0.dp (no padding) and 1.dp (hairline divider).
for f in "${EXISTING[@]:-}"; do
  under "$f" "$SRC_ROOT/presentation/" || continue

  # 5a — hardcoded Color(0x...) literals
  while IFS=: read -r line content; do
    [ -z "$line" ] && continue
    case "$content" in
      *//*|*\*\ *) continue ;;
    esac
    offending=$(printf '%s' "$content" | sed 's/^[[:space:]]*//')
    add_v "$f:$line — hardcoded color literal; use MaterialTheme.colorScheme.X (see [[material3-design-tokens]]): $offending"
  done < <(grep -nE "Color\(0[xX]" "$f" || true)

  # 5b — raw .dp integer literals (allowlist: 0.dp, 1.dp)
  while IFS=: read -r line content; do
    [ -z "$line" ] && continue
    case "$content" in
      *//*|*\*\ *) continue ;;
    esac
    offending=$(printf '%s' "$content" | sed 's/^[[:space:]]*//')
    add_v "$f:$line — raw .dp literal; use LocalSpacing.current.X (see [[spacing-scale-discipline]]): $offending"
  done < <(grep -nE "\b([2-9]|[0-9]{2,})\.dp\b" "$f" || true)

  # 5c — hardcoded fontSize = N.sp
  while IFS=: read -r line content; do
    [ -z "$line" ] && continue
    case "$content" in
      *//*|*\*\ *) continue ;;
    esac
    offending=$(printf '%s' "$content" | sed 's/^[[:space:]]*//')
    add_v "$f:$line — hardcoded fontSize; use MaterialTheme.typography.X (see [[material3-design-tokens]]): $offending"
  done < <(grep -nE "fontSize[[:space:]]*=[[:space:]]*[0-9]+\.sp" "$f" || true)
done

# ----- Check 6: Test hygiene (only test files in CHANGED_FILES) -------
# 6a — @Ignore without a TODO/#issue reference on the same or previous line.
# 6b — @Test with empty body (no assertion calls).
# 6c — Trivially-true assertions.
# 6d — Thread.sleep inside tests.
# 6e — runBlocking inside tests (must be runTest).
for f in "${EXISTING[@]:-}"; do
  case "$f" in
    app/src/test/*.kt|app/src/androidTest/*.kt) ;;
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
      add_v "$f:$line — @Ignore without TODO(#issue) reference: $offending"
    fi
  done < <(grep -nE "^[[:space:]]*@Ignore([[:space:]]|\()" "$f" || true)

  # 6b — @Test with empty body (look 20 lines ahead for any assertion-ish call)
  while IFS=: read -r line _; do
    [ -z "$line" ] && continue
    end=$((line + 20))
    body=$(sed -n "${line},${end}p" "$f")
    if ! printf '%s' "$body" | grep -qE "assert|expect|verify|should|Truth\."; then
      offending=$(sed -n "${line}p" "$f" | sed 's/^[[:space:]]*//')
      add_v "$f:$line — @Test with no assertions in body: $offending"
    fi
  done < <(grep -nE "^[[:space:]]*@Test[[:space:]]*$" "$f" || true)

  # 6c — Trivially-true assertions
  while IFS=: read -r line content; do
    [ -z "$line" ] && continue
    case "$content" in
      *//*) continue ;;
    esac
    offending=$(printf '%s' "$content" | sed 's/^[[:space:]]*//')
    add_v "$f:$line — trivially-true assertion: $offending"
  done < <(grep -nE "assertTrue\([[:space:]]*true[[:space:]]*\)|assertFalse\([[:space:]]*false[[:space:]]*\)" "$f" || true)

  # 6d — Thread.sleep
  while IFS=: read -r line content; do
    [ -z "$line" ] && continue
    case "$content" in
      *//*) continue ;;
    esac
    offending=$(printf '%s' "$content" | sed 's/^[[:space:]]*//')
    add_v "$f:$line — Thread.sleep in test (use runTest + advanceTimeBy): $offending"
  done < <(grep -nE "\bThread\.sleep\b" "$f" || true)

  # 6e — runBlocking
  while IFS=: read -r line content; do
    [ -z "$line" ] && continue
    case "$content" in
      *//*) continue ;;
      *import*runBlocking*) continue ;;
    esac
    offending=$(printf '%s' "$content" | sed 's/^[[:space:]]*//')
    add_v "$f:$line — runBlocking in test (use runTest from kotlinx-coroutines-test): $offending"
  done < <(grep -nE "\brunBlocking[[:space:]]*[\({]" "$f" || true)
done

# ----- Emit JSON --------------------------------------------------------
if [ "${#VIOLATIONS[@]}" -eq 0 ]; then
  printf '{"pass":true,"violations":[]}\n'
else
  out='{"pass":false,"violations":['
  i=0
  for v in "${VIOLATIONS[@]}"; do
    [ "$i" -gt 0 ] && out+=','
    out+="\"$(json_escape "$v")\""
    i=$((i + 1))
  done
  out+=']}'
  printf '%s\n' "$out"
fi
