#!/usr/bin/env bash
# Regression tests for the deterministic Android reviewer.
#
# The gate used to resolve exactly one source root (app/src/main/java/<pkg>), so on a
# multi-module project every check silently skipped and the script always answered
# {"pass":true,"violations":[]}. These tests pin the multi-module behaviour, the
# module-dependency checks, and the real-I/O test-clock exemption.
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/cmp-reviewer-test.XXXXXX")"
trap 'rm -rf "$work"' EXIT

pkg="com.demo.app"
pkg_path="com/demo/app"
script="$work/mp-reviewer-android.sh"
sed -e 's#{{PREFIX}}#mp#g' \
    -e 's#{{PROJECT_NAME}}#Demo#g' \
    -e "s#{{PACKAGE}}#$pkg#g" \
    -e "s#{{PACKAGE_PATH}}#$pkg_path#g" \
    "$repo/templates/android/scripts/{{PREFIX}}-reviewer-android.sh" > "$script"
bash -n "$script"

# ----- synthetic multi-module project ------------------------------------
proj="$work/proj"
mkdir -p "$proj"
cd "$proj"
git init -q .

for m in core/domain core/common core/network core/ads core/sync feature/wallet; do
  mkdir -p "$m/src/main/kotlin/$pkg_path/$m" "$m/src/test/kotlin/$pkg_path/$m"
  printf 'dependencies {\n}\n' > "$m/build.gradle.kts"
done

deps() { # deps <module> <dep...>
  local m="$1"; shift
  {
    printf 'dependencies {\n'
    for d in "$@"; do printf '    implementation(project(":%s"))\n' "${d//\//:}"; done
    printf '}\n'
  } > "$m/build.gradle.kts"
}

deps core/common
deps core/domain
deps core/network core/common
deps core/ads core/common core/domain core/network
deps core/sync core/common core/domain
deps feature/wallet core/domain core/common

# ----- baseline: a clean change reports pass ------------------------------
clean="core/ads/src/main/kotlin/$pkg_path/core/ads/CleanGateway.kt"
cat > "$clean" <<EOF
package $pkg.core.ads

import $pkg.core.domain.ads.AdRewardRepository

class CleanGateway(private val repo: AdRewardRepository)
EOF
out=$(bash "$script" "$clean")
printf '%s' "$out" | grep -q '"pass":true'
printf '%s' "$out" | grep -q '"violations":\[\]'

# ----- Check 7c: import from an undeclared module -------------------------
# This is the shape of the DI break that used to cost a full semantic-review cycle:
# :core:sync reaches into :core:ads without declaring it, so the graph only breaks
# at aggregate application build time.
undeclared="core/sync/src/main/kotlin/$pkg_path/core/sync/SharedSyncCoordinatorImpl.kt"
cat > "$undeclared" <<EOF
package $pkg.core.sync

import $pkg.core.ads.data.AdRewardRepositoryImpl

class SharedSyncCoordinatorImpl(private val rewards: AdRewardRepositoryImpl)
EOF
out=$(bash "$script" "$undeclared")
printf '%s' "$out" | grep -q '"pass":false'
printf '%s' "$out" | grep -q 'does not declare as a dependency'
printf '%s' "$out" | grep -q '"module-direction":1'

# ----- Check 7a: layering inversion --------------------------------------
deps core/network core/common feature/wallet
inverted="core/network/src/main/kotlin/$pkg_path/core/network/Transport.kt"
printf 'package %s.core.network\n\nclass Transport\n' "$pkg" > "$inverted"
out=$(bash "$script" "$inverted")
printf '%s' "$out" | grep -q '"pass":false'
printf '%s' "$out" | grep -q 'depends on higher layer :feature:wallet'
deps core/network core/common

# ----- Check 7b: declared cycle ------------------------------------------
deps core/ads core/common core/domain core/network core/sync
deps core/sync core/common core/domain core/ads
out=$(bash "$script" "core/ads/build.gradle.kts")
printf '%s' "$out" | grep -q 'module dependency cycle'
deps core/ads core/common core/domain core/network
deps core/sync core/common core/domain

# ----- Check 1: android import in a domain module -------------------------
domain_file="core/domain/src/main/kotlin/$pkg_path/core/domain/Money.kt"
cat > "$domain_file" <<EOF
package $pkg.core.domain

import android.content.Context

class Money(val ctx: Context)
EOF
out=$(bash "$script" "$domain_file")
printf '%s' "$out" | grep -q 'illegal Android import in domain'
printf '%s' "$out" | grep -q '"domain-purity":1'

# ----- Check 3: feature module ViewModel injecting a Repository ------------
vm="feature/wallet/src/main/kotlin/$pkg_path/feature/wallet/WalletViewModel.kt"
cat > "$vm" <<EOF
package $pkg.feature.wallet

class WalletViewModel(private val repo: WalletRepository)
EOF
out=$(bash "$script" "$vm")
printf '%s' "$out" | grep -q 'ViewModel injects Repository directly'

# ----- Check 6e: runBlocking needs an explicit real-I/O marker -------------
test_file="core/ads/src/test/kotlin/$pkg_path/core/ads/RewardTest.kt"
cat > "$test_file" <<EOF
package $pkg.core.ads

class RewardTest {
    @Test
    fun \`reads state\`() =
        runBlocking {
            assertEquals(1, 1 + 0)
        }
}
EOF
out=$(bash "$script" "$test_file")
printf '%s' "$out" | grep -q 'runBlocking without'
printf '%s' "$out" | grep -q '"test-clock":1'

cat > "$test_file" <<EOF
package $pkg.core.ads

class RewardTest {
    @Test
    fun \`reads state over real http\`() =
        // mp-real-io: MockWebServer response arrives in real time, virtual time would cancel it
        runBlocking {
            assertEquals(1, 1 + 0)
        }
}
EOF
out=$(bash "$script" "$test_file")
printf '%s' "$out" | grep -q '"pass":true'

# ----- Check 6b: a long but asserting test is not flagged ------------------
long_test="core/ads/src/test/kotlin/$pkg_path/core/ads/LongTest.kt"
{
  printf 'package %s.core.ads\n\nclass LongTest {\n    @Test\n    fun `long setup then asserts`() {\n' "$pkg"
  i=0
  while [ "$i" -lt 40 ]; do printf '        val v%s = %s\n' "$i" "$i"; i=$((i + 1)); done
  printf '        assertEquals(0, v0)\n    }\n}\n'
} > "$long_test"
out=$(bash "$script" "$long_test")
printf '%s' "$out" | grep -q '"pass":true'

# ----- --warn-only downgrades findings without failing --------------------
out=$(bash "$script" --warn-only "$undeclared")
printf '%s' "$out" | grep -q '"pass":true'
printf '%s' "$out" | grep -q '"violations":\[\]'
printf '%s' "$out" | grep -q 'does not declare as a dependency'
printf '%s' "$out" | grep -q '"module-direction":1'

# ----- single-module layout still works (back-compat) ---------------------
single="$work/single"
mkdir -p "$single"
cd "$single"
git init -q .
mkdir -p "app/src/main/java/$pkg_path/domain" "app/src/main/java/$pkg_path/presentation"
legacy="app/src/main/java/$pkg_path/domain/GetBalance.kt"
cat > "$legacy" <<EOF
package $pkg.domain

import android.os.Build

class GetBalance(val sdk: Int = Build.VERSION.SDK_INT)
EOF
out=$(bash "$script" "$legacy")
printf '%s' "$out" | grep -q 'illegal Android import in domain'

screen="app/src/main/java/$pkg_path/presentation/WalletScreen.kt"
printf 'package %s.presentation\n\nfun WalletScreen() {}\n' "$pkg" > "$screen"
out=$(bash "$script" "$screen")
printf '%s' "$out" | grep -q 'missing public <Name>Content'

# ----- output is always exactly one JSON line ----------------------------
# The no-arg form reads CHANGED_FILES from stdin, so it is fed an explicit empty
# stream here — leaving stdin attached to the caller's pipe would block forever.
[ "$(bash "$script" "$legacy" | wc -l | tr -d '[:space:]')" -eq 1 ]
[ "$(bash "$script" < /dev/null | wc -l | tr -d '[:space:]')" -eq 1 ]

printf 'test-reviewer-android: ok (%s)\n' "$work"
