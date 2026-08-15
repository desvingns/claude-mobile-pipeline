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

# A SPEC written in the team's own language must route on what it describes, not on
# which language it happens to be written in. This one crosses session auth and
# bounded polling; the English-only keyword lists scored it as routine work and sent
# it to the cheap developer with no independent critic.
cat > "$work/ru.md" <<'RUSPEC'
# Состояние награды
WHAT: клиент читает состояние с сервера и опрашивает его с нарастающей паузой.
CONSTRAINTS:
  - Поллинг ограничен по времени и обязан прекращаться при уходе экрана —
    никаких вечных корутин.
  - Поведение при 401 (сессия истекла): состояние сбрасывается.
RUSPEC
out=$(bash "$risk" --task feature --spec "$work/ru.md")
printf '%s' "$out" | grep -q '"risk":"high"'
printf '%s' "$out" | grep -q '"developer_tier":"powerful"'
printf '%s' "$out" | grep -q '"independent_critic":true'
printf '%s' "$out" | grep -q 'security_or_payment'
printf '%s' "$out" | grep -q 'state_or_concurrency'

# Declared front-matter signals are authoritative and collapse onto the same signal
# names as prose matching, so one concern is never paid for twice.
cat > "$work/declared.md" <<'DECLSPEC'
# Slice
Risk-signals: auth, di-wiring, concurrency
WHAT: nothing in this prose hints at any risk at all.
DECLSPEC
out=$(bash "$risk" --task feature --spec "$work/declared.md")
printf '%s' "$out" | grep -q '"risk":"high"'
printf '%s' "$out" | grep -q '"score":9'

# The same concern reached from prose AND a declared tag counts once.
cat > "$work/dup.md" <<'DUPSPEC'
# Slice
Risk-signals: auth, auth, security
WHAT: authentication and token handling.
DUPSPEC
out=$(bash "$risk" --task feature --spec "$work/dup.md")
printf '%s' "$out" | grep -q '"score":4'

# Scoring must not scale with diff size: five persistence files are one signal.
printf '# Feature\nRoom migration.\n' > "$work/persist.md"
out=$(bash "$risk" --task feature --spec "$work/persist.md" \
  --changed core/database/Migration1.kt --changed core/database/Migration2.kt \
  --changed core/database/Migration3.kt)
printf '%s' "$out" | grep -q '"score":8'

# ---- SPEC size gate ------------------------------------------------------
# The gate measures the DECLARED acceptance cross-product. It deliberately does
# not derive size from CHANGED_HINT: on the run this exists for, CHANGED_HINT
# named two modules while the work crossed seven plus a server grant, so every
# estimate built on it ranked the epic's worst SPEC among its smallest.
complexity=$(find "$repo/templates/common/scripts" -maxdepth 1 -name '*spec-complexity.sh' -print | head -1)

cat > "$work/big.md" <<'BIGSPEC'
# CloudSync gating
Acceptance-matrix: role=owner,participant; state=free,trial,active,grace,expired; transport=rpc,realtime; error=auth,network,server
BIGSPEC
out=$(bash "$complexity" --spec "$work/big.md")
printf '%s' "$out" | grep -q '"verdict":"split_recommended"'
printf '%s' "$out" | grep -q '"cells":60'
printf '%s' "$out" | grep -q '"matrix_declared":true'

cat > "$work/mid.md" <<'MIDSPEC'
# LocalOnly transition
Acceptance-matrix: role=owner,participant; reason=expired,killswitch,ad-window; snapshot=ok,failed
MIDSPEC
out=$(bash "$complexity" --spec "$work/mid.md")
printf '%s' "$out" | grep -q '"verdict":"warn"'
printf '%s' "$out" | grep -q '"cells":12'

printf '# Slice\nAcceptance-matrix: state=active,expired\n' > "$work/small.md"
out=$(bash "$complexity" --spec "$work/small.md")
printf '%s' "$out" | grep -q '"verdict":"ok"'
printf '%s' "$out" | grep -q '"cells":2'

# `—` is a real declaration: one behaviour for everyone, not a missing field.
printf '# Slice\nAcceptance-matrix: —\n' > "$work/none.md"
out=$(bash "$complexity" --spec "$work/none.md")
printf '%s' "$out" | grep -q '"verdict":"undeclared"'

# An absent line must never be guessed into a verdict from prose.
printf '# Slice\nWHAT: migration, auth, realtime, navigation everywhere.\n' > "$work/undecl.md"
out=$(bash "$complexity" --spec "$work/undecl.md")
printf '%s' "$out" | grep -q '"verdict":"undeclared"'
printf '%s' "$out" | grep -q '"matrix_declared":false'
printf '%s' "$out" | grep -q '"cells":0'

# The budget is configurable, and the frozen matrix is the full cross-product.
out=$(bash "$complexity" --spec "$work/mid.md" --cell-budget 8)
printf '%s' "$out" | grep -q '"verdict":"split_recommended"'
bash "$complexity" --spec "$work/mid.md" --freeze "$work/matrix.md" >/dev/null
[ "$(grep -c '^| [0-9]' "$work/matrix.md")" -eq 12 ]
grep -q 'role=owner · reason=killswitch · snapshot=failed' "$work/matrix.md"

out=$(bash "$complexity" --spec "$work/missing-file.md")
printf '%s' "$out" | grep -q '"ok":false'
[ "$(bash "$complexity" --spec "$work/mid.md" | wc -l | tr -d '[:space:]')" -eq 1 ]

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
