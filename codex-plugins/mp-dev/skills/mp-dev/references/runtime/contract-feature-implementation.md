<!-- mp-runtime-contract: feature-implementation -->

### Phase 2 — Implement

**Mode selection.** If the user passed `--tdd` after `--feature` → use the **TDD order** described at the end of this Phase (after Step 6). Otherwise use the **default order** below.

Before spawning any Phase 2 agent, apply the **Visual autotest device pre-flight (Android)** when the
SPEC is explicitly visual and requires visual/device autotests. If the gate fails, stop before
Developer/UI Designer/Tester/Runner.

Apply **Risk-based model and quality routing** now with `TASK=feature`. Resolve `SPEC_FILE`,
parse the initial route, and set `DEVELOPER_AGENT` / `VERIFIER_AGENT` before any implementation
agent. Feature always forces the full Verifier.

Spawn agents in sequence. Pass SPEC to each. Use `<platform>` resolution as described in the "Platform resolution" section above.

**Step 0 — UI Designer (pre-flight, Android only, presentation features only)**

This step runs **before Developer** in both default and TDD modes, but only when both conditions hold:
- Resolved platform is `android`
- `SPEC.LAYERS` contains `presentation`

Otherwise → skip to Step 1.

Spawn agent `mp-ui-designer-android` with prompt:
```
Prepare Material 3 design tokens for the feature below. Bootstrap ui/theme/ if missing; otherwise add only what's needed for SPEC.WHAT. Do NOT write any screens or business logic.
Return JSON: {"changed_files":[...], "commit":"hash", "tokens_added":[...], "conflicts":[...]}

SPEC:
[paste SPEC block]
```

Parse JSON. Then:
- If `conflicts` is non-empty → stop, surface the conflicts to the user, ask whether to overwrite (re-spawn with the conflicting tokens explicitly approved) or proceed without changing them.
- If `tokens_added` is non-empty → append a `DESIGN_TOKENS: <comma-separated list>` line to the SPEC block before passing it to Developer. The Developer's Critical Rules require tokens to be referenced by these exact names.
- If `tokens_added` is empty (no new tokens needed) → proceed to Step 1 with the original SPEC.

The ui-designer's commit (if any) lands on the same branch before Developer runs. Reviewer's Check 5 will later guard against any backsliding by Developer.

**Step 1 — Developer** (implement feature):
Spawn `DEVELOPER_AGENT` selected by the risk route with prompt:
```
Implement strictly per SPEC below. Return JSON: {"changed_files":[...], "commit":"hash"}

SPEC:
[paste SPEC block]
```

Re-run the risk router exactly once with the Developer's scoped `changed_files`; update
`DEVELOPER_AGENT`, `VERIFIER_AGENT`, `semantic_review`, and `independent_critic` from this
post-implementation result before review.

**Step 1.5 — Reviewer** (check layer boundaries) — **deterministic script**:
```bash
bash $MP_SCRIPTS/mp-reviewer-<platform>.sh [each changed_file from developer JSON, space-separated]
```

The script emits exactly one JSON line: `{"pass": bool, "violations": [...]}`. Parse it.

Fallback: if the script's exit code is non-zero or its output is not valid JSON, spawn the
`mp-reviewer-<platform>` agent with the same CHANGED_FILES list and use its output instead.

If `pass=false` → stop immediately, show violations to user. Do NOT proceed to Tester.

If the route requires semantic review, run the **Semantic review** stage from
`contract-risk-routing.md` now. A semantic failure blocks Tester.

Record telemetry for this step either way (see **Run telemetry**): `--agent reviewer`.

**Step 2 — Tester** (write comprehensive tests):
First derive `MODIFIED_EXISTING` — the subset of the developer's changed files that existed
BEFORE this task (modified, not added). Use the developer's commit:
`git show --name-status --format= <commit>` → lines starting with `M`. If the commit is
unavailable, pass `unknown` (the tester will infer).

Spawn agent `mp-tester-<platform>` with prompt:
```
Write tests per SPEC and for CHANGED_FILES below. Apply the Stale-Test Update Rule to MODIFIED_EXISTING.
Return JSON: {"test_files":[...], "screenshot_record_needed": bool, "stale_tests_reviewed":[...]}

SPEC:
[paste SPEC block]

CHANGED_FILES:
[output from developer agent]

MODIFIED_EXISTING:
[M-status files from the developer's commit, or "unknown"]
```

**Step 3 — Runner** (verify everything passes) — **deterministic script**:
```bash
bash $MP_SCRIPTS/mp-runner-<platform>.sh [true|false from tester.screenshot_record_needed]
```

The script emits exactly one JSON line with shape `{"pass": bool, "tests":..., "detekt|lint":..., "screenshots":..., "errors":[...]}`. Parse it.

Fallback: if the script's exit code is non-zero or its output is not valid JSON, spawn the
`mp-runner-<platform>` agent with `screenshot_record_needed=<bool>` and use its output instead.

**Step 4** — If Runner returns `pass=false`, attempt ONE automatic fix:

Spawn `DEVELOPER_AGENT` with prompt:
```
Fix the failing checks below. Do NOT add new logic or change behaviour — only make the checks pass.
Return JSON: {"changed_files":[...], "commit":"hash"}

SPEC:
[original SPEC block]

FAILED CHECKS:
tests:  [tests value from Runner]
lint:   [lint/detekt value from Runner]
errors: [errors array from Runner]
```

Then re-run `$MP_SCRIPTS/mp-runner-<platform>.sh` (same arguments as Step 3) and parse its JSON.
If the second run still returns `pass=false` → stop, show both failure reports to user and ask for guidance.

Once the runner outcome is FINAL (Step 3 passed, or the Step 4 retry resolved either way), record
telemetry (see **Run telemetry**): `--agent runner`, verdict from the final `pass`, metric
`tests=<...>;lint=<ok|fail>`, `--retry 1` when Step 4 ran.

If the route requires an independent critic, run that fresh-evidence pass now as defined in
`contract-risk-routing.md`. A critic failure blocks Verifier and push.

**Step 4.5 — Verifier** (static wiring checks + manual checklist gate before push):
Spawn `VERIFIER_AGENT` (full for every feature) with prompt:
```
Verify the implementation is wired into the app and generate a manual checklist.
Return JSON: {"pass": bool, "static_checks": {...}, "manual_checklist": [...]}

SPEC:
[paste SPEC block]

CHANGED_FILES:
[union of all changed files from Developer step(s)]

MODIFIED_EXISTING:
[same list passed to the Tester in Step 2]

TEST_FILES:
[test_files from the Tester's JSON]

COVERAGE_EXCEPTIONS:
[coverage_exceptions from the Tester's JSON, or []]

STALE_TESTS_REVIEWED:
[stale_tests_reviewed from the Tester's JSON, or []]
```

If Verifier returns `pass=false` → stop. Show `static_checks` failures to user and ask:
"Fix and continue? Describe the fix or run `/mp --bugfix`."

If Verifier returns `pass=true` → print `manual_checklist` verbatim to the user, then ask:
"Pre-push verification: run the checklist on emulator/device. Ready to push? (y/N)"

- If user answers **y** → proceed to Step 5 (Push).
- If user answers **N** → stop. Do NOT push. Wait for user feedback before doing anything else.

Record telemetry once the verifier resolves (see **Run telemetry**): `--agent verifier`.

**Step 5** — Push to remote (via the `Bash` tool):
```bash
# Token is provided via the GITHUB_TOKEN env var (configured in ~/.claude/settings.json,
# so it is available to every Bash invocation on all platforms).
# Reuse whatever remote is configured for `origin` instead of hard-coding the URL.
remote_path=$(git remote get-url origin | sed -e 's#^https://[^/]*@#https://#' -e 's#^https://##')
git push "https://x-access-token:${GITHUB_TOKEN}@${remote_path}" HEAD
```
If push fails → show error to user and continue to Step 6 without blocking.

**Step 6** — Always spawn `mp-docs` (it always refreshes `STATE.md`, even if `DOCUMENTATION.md`/`CLAUDE.md` need no changes):
```
SPEC: [paste]
CHANGED_FILES: [list]
Refresh STATE.md. Update DOCUMENTATION.md / CLAUDE.md only if genuinely new content (see mp-docs rules).
```

---

#### TDD mode (--tdd flag, optional)

If the user passed `--tdd`, replace the default Step 1..Step 6 above with the renumbered order below. Prompt formats are identical to default mode unless noted — refer to the matching default step for the full prompt template.

**Step 1 — Tester (RED phase).** Spawn `mp-tester-<platform>` with this prompt:

    red_phase=true

    Write failing unit tests (ViewModel + UseCase only) for SPEC.WHAT.
    Production code does not exist yet — that's the expected red signal.
    Return JSON per RED phase mode: {"test_files":[...], "screenshot_record_needed": false, "phase":"red", "expected_failures":[...]}

    SPEC:
    [paste SPEC block]

**Step 2 — Runner (expect red).** Run `bash $MP_SCRIPTS/mp-runner-<platform>.sh false` (no screenshots in RED phase) and parse the JSON output. **Interpret the result yourself:**

- If `tests` reports failures AND `lint/detekt` is `ok` AND the failures plausibly match `expected_failures` from Step 1 → red is correct, proceed to Step 3.
- If `tests` reports `0 failed` → tester didn't actually pin a contract. Stop and ask user.
- If failures look like compile errors on the **test code itself** (not on referenced-but-not-yet-existing production classes) → tester broke syntax. Stop and ask user.

**Step 2.5 — UI Designer (pre-flight, Android only, presentation features only).** Same conditions and protocol as default-mode Step 0 (above): only fires when platform is `android` AND `SPEC.LAYERS` contains `presentation`. Spawn `mp-ui-designer-android`, parse JSON, append `DESIGN_TOKENS:` to SPEC if `tokens_added` is non-empty, then proceed to Step 3.

**Step 3 — Developer (GREEN phase).** Spawn `DEVELOPER_AGENT` with this prompt:

    green_phase=true
    TEST_FILES: [list from Step 1]

    Implement production code until the listed tests are green. Do not modify the tests.
    Return JSON: {"changed_files":[...], "commit":"hash"}

    SPEC:
    [paste SPEC block]

**Step 3.5 — Reviewer.** Re-run risk routing once with the scoped CHANGED_FILES, then apply the
same deterministic + routed semantic-review sequence as default Step 1.5.

**Step 4 — Tester (default phase, second pass).** Spawn `mp-tester-<platform>` again with the default Step 2 prompt and the now-implemented CHANGED_FILES. This fills in `dao`, `compose-ui`, `screenshot` (or platform analogues) tests for any test types in SPEC.TEST_TYPES that the RED phase skipped.

**Step 5 — Runner (expect green).** Same as default Step 3. From here the chain matches the default order:

- **Step 6** — Auto-fix retry (same as default Step 4).
- **Step 6.25** — Independent critic when routed (same timing as default mode).
- **Step 6.5** — Routed full Verifier (same as default Step 4.5).
- **Step 7** — Push (same as default Step 5).
- **Step 8** — Docs (same as default Step 6).
