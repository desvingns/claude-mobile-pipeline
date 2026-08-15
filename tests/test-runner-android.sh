#!/usr/bin/env bash
# Regression tests for the scoped Android runner's task resolution.
#
# Gradle test task names are per module: an Android module answers to
# testDebugUnitTest, a pure JVM module only to test. The scoped runner used to
# address every module with testDebugUnitTest, so a scope containing a JVM module
# failed Gradle *configuration* and was reported as a compile failure — a healthy
# module looked broken and cost a diagnosis cycle. These tests pin the per-module
# resolution and the task_not_found carve-out.
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/cmp-runner-test.XXXXXX")"
trap 'rm -rf "$work"' EXIT

script="$work/mp-runner-android.sh"
sed -e 's#{{PREFIX}}#mp#g' -e 's#{{PROJECT_NAME}}#Demo#g' \
    "$repo/templates/android/scripts/{{PREFIX}}-runner-android.sh" > "$script"
bash -n "$script"

proj="$work/proj"
mkdir -p "$proj"
cd "$proj"
git init -q .

# A stub gradlew records the task line instead of building, so the test pins the
# command the runner composes without needing a JVM or the Android SDK.
cat > gradlew <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> .tasks.log
exit 0
STUB
chmod +x gradlew

# :core:ads is an Android library; :core:domain and :core:common are pure JVM.
mkdir -p core/ads/src/main core/domain/src/main core/common/src/main
printf 'plugins {\n    id("com.android.library")\n}\n' > core/ads/build.gradle.kts
printf 'plugins {\n    kotlin("jvm")\n}\n'             > core/domain/build.gradle.kts
printf 'plugins {\n    kotlin("jvm")\n}\n'             > core/common/build.gradle.kts

# ----- per-module task resolution ----------------------------------------
: > .tasks.log
out=$(bash "$script" --scope ":core:ads :core:domain")
tasks=$(cat .tasks.log)
printf '%s' "$tasks" | grep -q ':core:ads:testDebugUnitTest'
printf '%s' "$tasks" | grep -q ':core:domain:test\b'
printf '%s' "$tasks" | grep -qv ':core:domain:testDebugUnitTest'
printf '%s' "$out" | grep -q '"mode":"scoped"'

# An Android module recognised through its manifest rather than its plugin block
# (convention plugins apply the Android plugin without an `android {}` block).
mkdir -p core/ui/src/main
printf 'plugins {\n    id("demo.android.library")\n}\n' > core/ui/build.gradle.kts
printf '<manifest package="com.demo.ui"/>\n' > core/ui/src/main/AndroidManifest.xml
: > .tasks.log
bash "$script" --scope ":core:ui" >/dev/null
grep -q ':core:ui:testDebugUnitTest' .tasks.log

# ----- a module we cannot locate is task_not_found, not a code failure ----
out=$(bash "$script" --scope ":core:missing")
printf '%s' "$out" | grep -q '"error_kind":"task_not_found"'
printf '%s' "$out" | grep -q '"pass":false'
printf '%s' "$out" | grep -q 'no gradle build file'
[ "$(printf '%s' "$out" | wc -l | tr -d '[:space:]')" -eq 0 ]

# ----- gradle's own "task not found" is carved out of compile failures ----
cat > gradlew <<'STUB'
#!/usr/bin/env bash
printf "Task 'testDebugUnitTest' not found in project ':core:domain'.\n"
exit 1
STUB
chmod +x gradlew
out=$(bash "$script" --scope ":core:domain")
printf '%s' "$out" | grep -q '"error_kind":"task_not_found"'
printf '%s' "$out" | grep -qv 'compile/config failure'

# A genuine compile break is still a failure, and must NOT be labelled
# task_not_found — that carve-out exists to stop a developer chasing a compile
# error that was never there, so mislabelling in this direction is the costly one.
cat > gradlew <<'STUB'
#!/usr/bin/env bash
printf 'e: file.kt:1:1 unresolved reference\nBUILD FAILED\n'
exit 1
STUB
chmod +x gradlew
out=$(bash "$script" --scope ":core:domain")
printf '%s' "$out" | grep -q '"pass":false'
printf '%s' "$out" | grep -q 'build failed'
printf '%s' "$out" | grep -qv 'task_not_found'
printf '%s' "$out" | grep -q 'unresolved reference'

# ----- MP_TEST_TASK still overrides everything ---------------------------
cat > gradlew <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> .tasks.log
exit 0
STUB
chmod +x gradlew
: > .tasks.log
MP_TEST_TASK=testReleaseUnitTest bash "$script" --scope ":core:domain" >/dev/null
grep -q ':core:domain:testReleaseUnitTest' .tasks.log

# ----- an empty scope fails loudly instead of running everything ----------
out=$(bash "$script" --scope "")
printf '%s' "$out" | grep -q '"pass":false'
printf '%s' "$out" | grep -q 'requires at least one module'

printf 'test-runner-android: ok (%s)\n' "$work"
