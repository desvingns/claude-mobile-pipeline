#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
result="$(bash "$repo/eval/runner.sh")"
printf '%s' "$result" | grep -q '"ok":true'
printf '%s' "$result" | grep -q '"passed":3'

out="$(mktemp -d "${TMPDIR:-/tmp}/cmp-eval-candidates.XXXXXX")"
ingest="$(bash "$repo/eval/ingest-low-feedback.sh" \
  --runs "$repo/eval/fixtures/telemetry/structured.jsonl" --out "$out")"
printf '%s' "$ingest" | grep -q '"matched_events":1'
printf '%s' "$ingest" | grep -q '"created":1'
candidate="$(find "$out" -name 'feedback-*.json' -print | head -1)"
[ -n "$candidate" ]
grep -q '"status": "needs-human-rubric"' "$candidate"
grep -q '"correlation_id": "epic-42"' "$candidate"

again="$(bash "$repo/eval/ingest-low-feedback.sh" \
  --runs "$repo/eval/fixtures/telemetry/structured.jsonl" --out "$out")"
printf '%s' "$again" | grep -q '"created":0'
printf '%s' "$again" | grep -q '"skipped_existing":1'

printf 'test-eval: ok (%s)\n' "$out"
