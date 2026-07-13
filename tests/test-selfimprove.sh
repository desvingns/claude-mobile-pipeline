#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/cmp-selfimprove-test.XXXXXX")"
mkdir -p "$work/selfimprove"
git -C "$work" init -q
printf 'fixture\n' > "$work/README.md"
git -C "$work" add README.md
git -C "$work" -c user.name=cmp-test -c user.email=cmp@example.invalid commit -qm fixture

health="$(bash "$repo/templates/common/scripts/{{PREFIX}}-retro.sh" --root "$work" --health)"
printf '%s' "$health" | grep -q '"health":"dormant"'

legacy="$(REFLECT_AFTER=2 bash "$repo/templates/common/scripts/{{PREFIX}}-record-run.sh" \
  --root "$work" --agent reviewer --verdict pass --tokens-in 100 --tokens-out 20 --cost approx)"
printf '%s' "$legacy" | grep -q '"retro_due":false'
head -1 "$work/selfimprove/runs/"*.jsonl | grep -q '"usage_source":"estimated"'

structured="$(REFLECT_AFTER=2 bash "$repo/templates/common/scripts/{{PREFIX}}-record-run.sh" \
  --root "$work" --agent verifier --verdict partial --model gpt-fixture \
  --tokens-in 200 --tokens-out 40 --tokens-cached 125 --tokens-reasoning 15 \
  --cost-usd 0.0125 --duration-ms 3456 --usage-source provider \
  --correlation-id epic-42 --retry 1)"
printf '%s' "$structured" | grep -q '"retro_due":true'
event="$(tail -1 "$work/selfimprove/runs/"*.jsonl)"
printf '%s' "$event" | grep -q '"tokens_cached":125'
printf '%s' "$event" | grep -q '"tokens_reasoning":15'
printf '%s' "$event" | grep -q '"cost_usd":0.0125'
printf '%s' "$event" | grep -q '"duration_ms":3456'
printf '%s' "$event" | grep -q '"usage_source":"provider"'
printf '%s' "$event" | grep -q '"correlation_id":"epic-42"'
invalid="$(bash "$repo/templates/common/scripts/{{PREFIX}}-record-run.sh" --root "$work" \
  --agent runner --verdict pass --tokens-in 1 --usage-source guessed)"
printf '%s' "$invalid" | grep -q '"ok":false'
[ "$(cat "$work/selfimprove/runs/"*.jsonl | grep -c '"agent"')" -eq 2 ]
for bad_cost in .5 1. 01; do
  invalid_cost="$(bash "$repo/templates/common/scripts/{{PREFIX}}-record-run.sh" --root "$work" \
    --agent runner --verdict pass --cost-usd "$bad_cost")"
  printf '%s' "$invalid_cost" | grep -q '"ok":false'
done
[ "$(cat "$work/selfimprove/runs/"*.jsonl | grep -c '"agent"')" -eq 2 ]

retro="$(bash "$repo/templates/common/scripts/{{PREFIX}}-retro.sh" --root "$work")"
printf '%s' "$retro" | grep -q '"ok":true'
report="$(printf '%s' "$retro" | sed -n 's/.*"retro":"\([^"]*\)".*/\1/p')"
grep -q 'cached input: 125' "$report"
grep -q 'reasoning output: 15' "$report"
grep -q 'Cost (structured): $0.012500' "$report"
grep -q 'duration: 3456 ms total' "$report"
grep -q 'correlated events: 1' "$report"
grep -q 'Usage source: provider 1 · estimated 1 · unspecified 0' "$report"

# Root-kit parity: copy it to a fixture root so this test never writes telemetry
# into the mobile-pipeline checkout itself.
root_work="$(mktemp -d "${TMPDIR:-/tmp}/cmp-root-retro-test.XXXXXX")"
mkdir -p "$root_work/selfimprove"
cp "$repo/selfimprove/record-run.sh" "$repo/selfimprove/retro.sh" "$root_work/selfimprove/"
root_record="$(bash "$root_work/selfimprove/record-run.sh" --agent feedback --verdict fail \
  --metric 'score=2' --tokens-cached 9 --duration-ms 10 --usage-source provider \
  --correlation-id low-1)"
printf '%s' "$root_record" | grep -q '"ok":true'
tail -1 "$root_work/selfimprove/runs/"*.jsonl | grep -q '"usage_source":"provider"'
if bash "$root_work/selfimprove/record-run.sh" --agent feedback --verdict pass \
  --cost-usd .5 >/dev/null 2>&1; then
  echo 'expected root record-run to reject a non-JSON decimal' >&2
  exit 1
fi
[ "$(cat "$root_work/selfimprove/runs/"*.jsonl | grep -c '"agent"')" -eq 1 ]
root_retro="$(bash "$root_work/selfimprove/retro.sh")"
printf '%s' "$root_retro" | grep -q '"ok":true'
grep -q 'low (<=3): 1' "$root_work/selfimprove/retro/"retro-*.md

printf 'test-selfimprove: ok (%s)\n' "$work"
