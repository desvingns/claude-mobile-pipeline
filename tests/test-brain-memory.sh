#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
helper="$repo/templates/common/scripts/{{PREFIX}}-brain-memory.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/cmp-brain-memory-test.XXXXXX")"
brain="$work/brain"
mkdir -p "$brain/core" "$brain/domains" "$brain/inbox"
printf '# Fixture profile\n\n- Prefers concise reports.\n' > "$brain/core/user-profile.md"
printf '# INDEX\n\n## domains\n- [testing](domains/testing.md) — deterministic testing and fixtures\n' > "$brain/INDEX.md"
printf '%s\n' '# Testing' '' '- Keep deterministic fixtures small and evidence-backed.' > "$brain/domains/testing.md"

before="$(cksum "$brain/core/user-profile.md")"
resolved="$(MP_USER_PROFILE="$brain/core/user-profile.md" bash "$helper" resolve --brain "$brain")"
printf '%s' "$resolved" | grep -q '"profile_read_only":true'
printf '%s' "$resolved" | grep -q '"curated_writes":false'

context="$(bash "$helper" context --brain "$brain" --tags testing --budget 60 --max-files 1)"
printf '%s' "$context" | grep -q '"files":\["domains/testing.md"\]'
approx="$(printf '%s' "$context" | sed -nE 's/.*"approx_tokens":([0-9]+).*/\1/p')"
[ -n "$approx" ] && [ "$approx" -le 60 ]

args=(append-candidate --brain "$brain" --kind user-preference --project Fixture
  --text 'Prefers concise fit reports' --evidence 'Fixture, 2026-07-13, fit round 1'
  --source fixture)
first="$(bash "$helper" "${args[@]}")"
second="$(bash "$helper" "${args[@]}")"
printf '%s' "$first" | grep -q '"queued":true'
printf '%s' "$first" | grep -q '"deduplicated":false'
printf '%s' "$second" | grep -q '"deduplicated":true'
first_id="$(printf '%s' "$first" | sed -nE 's/.*"candidate_id":"([^"]+)".*/\1/p')"
second_id="$(printf '%s' "$second" | sed -nE 's/.*"candidate_id":"([^"]+)".*/\1/p')"
[ -n "$first_id" ] && [ "$first_id" = "$second_id" ]

candidate="$(find "$brain/inbox" -type f -name '*.md' -print -quit)"
[ -n "$candidate" ]
grep -q -- "- id: $first_id" "$candidate"
grep -q -- '- evidence: Fixture, 2026-07-13, fit round 1' "$candidate"
grep -q -- '- status: NEW' "$candidate"
[ "$(grep -c -- "- id: $first_id" "$candidate")" -eq 1 ]
[ "$before" = "$(cksum "$brain/core/user-profile.md")" ]

# An explicit invalid root must not fall back to a real personal brain. Append is
# fire-and-forget: one JSON line, exit 0, queued=false.
missing_args=(append-candidate --brain "$work/missing" --kind brain-level
  --project Fixture --text 'A general lesson' --evidence 'Fixture, test')
missing="$(bash "$helper" "${missing_args[@]}")"
printf '%s' "$missing" | grep -q '"queued":false'
printf '%s' "$missing" | grep -q '"curated_writes":false'
[ "$(printf '%s\n' "$missing" | wc -l | tr -d ' ')" -eq 1 ]

# Local policy rejects excluded categories without embedding machine-specific terms in
# the shared template. Project/source fields are covered as well as text/evidence.
blocked="$(BRAIN_EXCLUDE_RE='internal-only' bash "$helper" append-candidate --brain "$brain" \
  --kind brain-level --project 'Internal-only fixture' --text 'A portable lesson' \
  --evidence 'Fixture, policy check')"
printf '%s' "$blocked" | grep -q '"queued":false'
printf '%s' "$blocked" | grep -q '"curated_writes":false'
printf '%s' "$blocked" | grep -q '"candidate rejected by the local exclusion policy"'

printf 'test-brain-memory: ok (%s, context=%s tokens)\n' "$work" "$approx"
