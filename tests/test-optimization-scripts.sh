#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/cmp-optimization-test.XXXXXX")"
risk=$(find "$repo/templates/common/scripts" -maxdepth 1 -name '*risk-route.sh' -print | head -1)
spec_scripts="$repo/templates/spec/skills/app-spec-creator/scripts"

printf '# Bugfix\nFix a local label typo.\n' > "$work/low.md"
printf '# Feature\nAuthenticated payment with Room schema migration, navigation, offline sync.\n' > "$work/high.md"

out=$(bash "$risk" --task bugfix --spec "$work/low.md" --changed app/src/main/Foo.kt)
printf '%s' "$out" | grep -q '"risk":"low"'
printf '%s' "$out" | grep -q '"developer_tier":"standard"'
printf '%s' "$out" | grep -q '"verifier":"lite"'

out=$(bash "$risk" --task feature --spec "$work/high.md" --visual --changed app/src/main/AndroidManifest.xml)
printf '%s' "$out" | grep -q '"risk":"high"'
printf '%s' "$out" | grep -q '"developer_tier":"powerful"'
printf '%s' "$out" | grep -q '"semantic_review":true'
printf '%s' "$out" | grep -q '"independent_critic":true'

out=$(bash "$risk" --task feature --spec "$work/missing.md")
printf '%s' "$out" | grep -q '"ok":false'

out=$(bash "$spec_scripts/spec-cache.sh" fingerprint "$work/cache" intake "$work/low.md")
fingerprint=$(printf '%s' "$out" | sed -nE 's/.*"fingerprint":"([a-f0-9]+)".*/\1/p')
[ -n "$fingerprint" ]
bash "$spec_scripts/spec-cache.sh" record "$work/cache" intake "$fingerprint" | grep -q '"ok":true'
bash "$spec_scripts/spec-cache.sh" check "$work/cache" intake "$fingerprint" | grep -q '"hit":true'
bash "$spec_scripts/spec-cache.sh" check "$work/cache" intake deadbeef | grep -q '"hit":false'

bash "$spec_scripts/spec-usage.sh" "$work/agent-usage.jsonl" \
  --role requirements-author --phase requirements --model fixture \
  --input-chars 401 --output-chars 40 --duration-ms 5 --cache-hit false \
  | grep -q '"estimated":true'
bash "$spec_scripts/spec-usage.sh" "$work/agent-usage.jsonl" \
  --role spec-evaluator --phase evaluator --model fixture --reasoning high \
  --input-tokens 100 --output-tokens 20 --cached-tokens 50 --reasoning-tokens 5 \
  --duration-ms 10 --cache-hit true | grep -q '"estimated":false'
[ "$(wc -l < "$work/agent-usage.jsonl" | tr -d '[:space:]')" -eq 2 ]

assert_single_error_json() {
  local output="$1" lines
  lines=$(printf '%s\n' "$output" | wc -l | tr -d '[:space:]')
  [ "$lines" -eq 1 ]
  printf '%s\n' "$output" | grep -Eq '^\{"ok":false,"error":".*"\}$'
}

missing_value_options=(
  --role --phase --model --reasoning --correlation
  --input-tokens --output-tokens --cached-tokens --reasoning-tokens
  --input-chars --output-chars --duration-ms --retry --cache-hit --status
)
for option in "${missing_value_options[@]}"; do
  out=$(bash "$spec_scripts/spec-usage.sh" "$work/negative-usage.jsonl" "$option")
  assert_single_error_json "$out"
done

out=$(bash "$spec_scripts/spec-usage.sh")
assert_single_error_json "$out"
out=$(bash "$spec_scripts/spec-usage.sh" --role fixture)
assert_single_error_json "$out"
out=$(bash "$spec_scripts/spec-usage.sh" "$work/negative-usage.jsonl" --unknown value)
assert_single_error_json "$out"
out=$(bash "$spec_scripts/spec-usage.sh" "$work/negative-usage.jsonl" --role --phase fixture)
assert_single_error_json "$out"
out=$(bash "$spec_scripts/spec-usage.sh" "$work/negative-usage.jsonl" \
  --role fixture --phase quality --input-tokens nope --output-tokens 1)
assert_single_error_json "$out"

spec="$work/spec"
mkdir -p "$spec/acceptance" "$spec/fit"
for file in 00_manifest.yaml constitution.md product-brief.md design.md nfr.md a11y.md \
  security-privacy.md analytics.md i18n.md risks.md estimate.md deviations.md; do
  printf 'fixture\n' > "$spec/$file"
done
printf '%s\n' '- **FR-001** — WHEN the user acts, THE SYSTEM SHALL respond.' > "$spec/requirements.md"
printf '%s\n' '**US-001** — As a user, I want a response.' '- FR-IDs: FR-001' > "$spec/user-stories.md"
printf '%s\n' 'Feature: Fixture' '@US-001 @FR-001' 'Scenario: Works' '  Given a fixture' > "$spec/acceptance/fixture.feature"
printf 'screen_id,reference\nS01,01.png\n' > "$spec/fit/registry.csv"
printf '# S01\n' > "$spec/fit/S01.md"
out=$(bash "$spec_scripts/spec-preflight.sh" "$spec" --clone --out "$work/eval-preflight.json")
printf '%s' "$out" | grep -q '"pass":true'
[ -s "$work/eval-preflight.json" ]

printf 'test-optimization-scripts: ok (%s)\n' "$work"
