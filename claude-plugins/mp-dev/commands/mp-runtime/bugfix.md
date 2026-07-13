<!-- mp-runtime-mode: bugfix -->
<!-- mp-runtime-contracts: startup execution platform device telemetry risk-routing post-ship rules rules-implementation rules-learning -->

## Workflow: --bugfix

### Phase 1 — Locate

Read bug description. If reproduction steps unclear, ask only:
- Which screen / flow?
- Actual vs expected behaviour?

Skip questions if bug location is obvious.

**Runtime / persistence / cold-start bug flag.** If the reported bug involves visible UI state not
surviving app restart (cold-start, process death, re-launch), persisted data that disappears or does
not round-trip after restart, or a crash / wrong behaviour observed on a running app (not a
compile/lint failure) — tag the bugfix `RUNTIME_BUG: true` in the SPEC CONSTRAINTS. This tag
activates the reproduction gate in Phase 2 Step 0.

### Phase 2 — Fix

Before spawning Developer, apply the **Visual autotest device pre-flight (Android)** when the bugfix is
explicitly visual and requires visual/device autotests. If the gate fails, stop before any fix work.

**Step 0 — Reproduce the user's literal steps (mandatory when `RUNTIME_BUG: true`; strongly
recommended for all runtime bugs).**

Do NOT hypothesise a root cause and write a test to match it. Reproduce the user's LITERAL reported
steps first to confirm the failure before any code is written.

For Android runtime/cold-start bugs (`RUNTIME_BUG: true`):
1. Build and install a debug APK on the connected device:
   ```bash
   ./gradlew :app:assembleDebug && adb install -r app/build/outputs/apk/debug/app-debug.apk
   ```
   If no device is connected → apply the **Visual autotest device pre-flight** gate; stop if none is available.
2. Drive the user's reported steps exactly as described — the literal sequence, with the user's
   actual locale/data/currency/settings. Do NOT substitute a self-constructed scenario that you
   believe is equivalent.
3. Capture evidence of failure (logcat snippet, observed wrong state, screenshot).
4. Only if the bug is confirmed reproduced → proceed to Step 1 (Developer). If it does NOT
   reproduce with the literal steps → stop, report non-reproduction to the user, and ask for
   clarification. Do NOT invent an alternative scenario, and do NOT write a regression test for
   an invented scenario — a test that passes by construction proves nothing about the user's bug.

Persist the resolved bugfix SPEC to `SPEC_FILE`, then apply **Risk-based model and quality
routing** with `TASK=bugfix`. Resolve `DEVELOPER_AGENT` / `VERIFIER_AGENT`; only a validated
low-risk route may select the lite Verifier. Routing failure uses the safe powerful/full fallback.

**Step 1 — Developer**:
Spawn `DEVELOPER_AGENT` selected by the risk route with prompt:
```
Fix bug per SPEC. Write regression test (red→green).
Return JSON: {"changed_files":[...], "commit":"hash"}

SPEC:
TASK: bugfix
PLATFORM: [android | ios — only required when project has multiple platforms]
WHAT: [root cause one sentence]
LAYERS: [affected layers]
CHANGED_HINT: [files to read]
TEST_TYPES: unit
CONSTRAINTS: regression test required, conventional commit fix:
```

Re-run the risk router exactly once with one `--changed` argument per scoped changed file and
replace the initial route with this post-implementation result.

**Step 1.5 — Reviewer** (if the fix touches `presentation/` or `domain/`, or any routed semantic
pass is required) — **deterministic script**:
```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/mp-reviewer-<platform>.sh [each changed_file from developer JSON, space-separated]
```
Parse JSON. Fallback to spawning `mp-reviewer-<platform>` agent on script error.
If `pass=false` → stop, show violations.

If the route requires semantic review, run the **Semantic review** stage from
`contract-risk-routing.md` after the deterministic reviewer passes. A semantic failure blocks
Runner.

**Step 2 — Runner** — **deterministic script**:
```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/mp-runner-<platform>.sh false
```
Parse JSON. Fallback to spawning `mp-runner-<platform>` agent on script error.

**Step 3** — If `pass=false`, attempt ONE automatic fix:

Spawn `DEVELOPER_AGENT` with:
```
Fix the failing checks below. Do NOT change the bugfix logic — only make checks pass.
Return JSON: {"changed_files":[...], "commit":"hash"}

ORIGINAL SPEC: [bugfix SPEC block]
FAILED CHECKS: [errors from Runner]
```

Then re-run `${CLAUDE_PLUGIN_ROOT}/scripts/mp-runner-<platform>.sh false`. If still `pass=false` → stop, show failures to user.

Record telemetry for the reviewer and the FINAL runner outcome (see **Run telemetry**), as in `--feature`.

**Step 3.5 — Device re-verification (mandatory when `RUNTIME_BUG: true`).**
After Runner passes, rebuild and install the fixed APK on device and drive the user's LITERAL
reproduction steps again to confirm the wrong behaviour is gone:
```bash
./gradlew :app:assembleDebug && adb install -r app/build/outputs/apk/debug/app-debug.apk
```
Record result as `device_repro_confirmed: fixed` or `device_repro_confirmed: still-failing`.
If `still-failing` → stop and report; do NOT push. A green self-authored regression test is NOT
sufficient to declare a user-reported runtime bug fixed. Both must be true before push:
- `regression_test: green` — the automated check passes
- `device_repro_confirmed: fixed` — the user's literal scenario re-run on device no longer fails

**Step 3.75 — Routed Verifier (mandatory before every bugfix push).**

If `independent_critic=true`, first run the fresh-evidence critic from
`contract-risk-routing.md`; failure blocks the chain. Then spawn `VERIFIER_AGENT`
(`mp-verifier-lite-android` only for a validated low-risk Android route, otherwise the
full `mp-verifier-<platform>`) with:

```
Verify this bugfix, its regression evidence, and app wiring. Return JSON per your output spec.

SPEC_FILE: [resolved path]
CHANGED_FILES: [union of scoped changed files]
TEST_FILES: [changed regression-test files, or []]
REVIEW_EVIDENCE: [deterministic + semantic reviewer payloads]
RUNNER_EVIDENCE: [final runner payload]
DEVICE_REPRO: [fixed | not-applicable]
```

If `pass=false`, stop and show the failed checks. If `pass=true`, print any
`manual_checklist` and ask "Bugfix verification passed. Ready to push? (y/N)". Only `y`
continues. Record fire-and-forget verifier telemetry either way.

**Step 4** — Push to remote (via the `Bash` tool):
```bash
remote_path=$(git remote get-url origin | sed -e 's#^https://[^/]*@#https://#' -e 's#^https://##')
git push "https://x-access-token:${GITHUB_TOKEN}@${remote_path}" HEAD
```
If push fails → show error to user and continue without blocking.

**Step 5 — Docs** (always — refreshes STATE.md):
Spawn `mp-docs` with SPEC and CHANGED_FILES. It always refreshes `STATE.md`; it updates `DOCUMENTATION.md`/`CLAUDE.md` only if the fix reveals a new architectural decision.

### Phase 3 — Report

```
fix: [description]
   Root cause: [one sentence]
   Commit: [hash]
   Tests: [N passed]
   Lint:  ok
   Regression test: green | not-applicable
   Device repro confirmed: fixed | not-applicable (non-runtime bug)
   Pushed: yes / failed: [reason]
```

---
