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

Spawn agent `{{PREFIX}}-ui-designer-android` with prompt:
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
# Add --warn-only when .claude/{{PREFIX}}/config.json sets "reviewerMode": "warn-only".
bash .claude/scripts/{{PREFIX}}-reviewer-<platform>.sh [--warn-only] [each changed_file from developer JSON, space-separated]
```

The script emits exactly one JSON line: `{"pass": bool, "violations": [...], "warnings": [...], "by_check": {...}}`. Parse it.

Fallback: if the script's exit code is non-zero or its output is not valid JSON, spawn the
`{{PREFIX}}-reviewer-<platform>` agent with the same CHANGED_FILES list and use its output instead.

If `pass=false` → stop immediately, show violations to user. Do NOT proceed to Tester.

`warnings` is never empty-by-accident: it is populated only when the project runs the reviewer with
`--warn-only` (set `"reviewerMode": "warn-only"` in `.claude/{{PREFIX}}/config.json`), which a
project uses while adopting checks that have never run against its codebase. Surface warnings to
the user with their `by_check` counts and continue — they are adoption data, not a gate. A project
staying in `warn-only` indefinitely has an unenforced reviewer; say so once when you report them.

The `usecase-test` check reports a touched use case with no `<Name>Test.kt` of its own. That is the
same rule the full verifier applies at the very end of the run; it is enforced here so the fix costs
one Tester pass instead of a repair plus a full re-verify after the suite has already run green.

If the route requires semantic review, run the **Semantic review** stage from
`contract-risk-routing.md` now — including the frozen acceptance matrix and the `coverage` field.
A semantic failure blocks Tester.

Record telemetry for this step either way (see **Run telemetry**): `--agent reviewer`.

**Step 2 — Tester** (write comprehensive tests):
First derive `MODIFIED_EXISTING` — the subset of the developer's changed files that existed
BEFORE this task (modified, not added). Use the developer's commit:
`git show --name-status --format= <commit>` → lines starting with `M`. If the commit is
unavailable, pass `unknown` (the tester will infer).

Spawn agent `{{PREFIX}}-tester-<platform>` with prompt:
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

Run it in two stages. The scoped stage answers "did this change work"; the full stage is the
release gate. Using the full run for both makes every repair iteration pay a release-gate price,
and it turns the runner into the discovery mechanism for problems the reviewers should have found.

**3a — scoped run** (skip when the change touches only one module and that module is `app`):
```bash
bash .claude/scripts/{{PREFIX}}-runner-<platform>.sh --scope "<modules touched by CHANGED_FILES>"
```
Derive the module list from the changed paths (the segment before `/src/`). It returns
`"mode":"scoped"` and runs unit tests for those modules only — no detekt, lint, coverage, or
screenshots. Iterate here while fixing.

**3b — full run** (mandatory, exactly once, after the scoped stage is green):
```bash
bash .claude/scripts/{{PREFIX}}-runner-<platform>.sh [true|false from tester.screenshot_record_needed]
```

Each stage emits exactly one JSON line with shape `{"pass": bool, "mode":"scoped|full", "tests":..., "detekt|lint":..., "screenshots":..., "errors":[...]}`. Parse it.

Never substitute a scoped run for the full one: a scoped run cannot see a break in a module it did
not touch, and that is precisely the failure a multi-module change causes.

Fallback: if the script's exit code is non-zero or its output is not valid JSON, spawn the
`{{PREFIX}}-runner-<platform>` agent with `screenshot_record_needed=<bool>` and use its output instead.

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

Then re-run `.claude/scripts/{{PREFIX}}-runner-<platform>.sh` (same arguments as Step 3) and parse its JSON.
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
"Fix and continue? Describe the fix or run `/{{PREFIX}} --bugfix`."

**Step 4.6 — Scoped fit check (Android clone projects, presentation features only).**

Run this BEFORE the push gate when all of these hold:
- resolved platform is `android`, AND
- `SPEC.LAYERS` contains `presentation`, AND
- the project has clone references — `spec/fit/registry.csv` exists, or `.claude/{{PREFIX}}/config.json`
  sets `referenceScreenshotsDir`.

Spawn `{{PREFIX}}-fit-android` scoped to **only the screen(s) this SPEC touched** (not the whole app —
that is what `/{{PREFIX}} --fit` is for). Pass the changed presentation files so it can resolve which
`screen_id`s are in scope.

- Divergences below `fitThreshold` → report them to the user *before* the push question, and
  include them in the checklist so the decision is informed.
- No usable device/reference → skip with a one-line note (`fit: skipped — no device`) and continue
  to the push gate. Do NOT hard-block here: an explicitly visual SPEC was already stopped by the
  visual device pre-flight at the top of Phase 2, and a non-visual presentation tweak must not
  require a booted emulator.

Rationale: a visual miss caught here costs one scoped multimodal call; the same miss caught after
push costs a full re-run of the whole pipeline. Post-ship feedback shows visual divergence is a
dominant rework driver, and `--fit` today only runs after the user has already rejected the result.

If Verifier returns `pass=true` → print `manual_checklist` verbatim to the user, then ask:
"Pre-push verification: run the checklist on emulator/device. Ready to push? (y/N)"

- If user answers **y** → proceed to Step 5 (Push).
- If user answers **N** → stop. Do NOT push. Wait for user feedback before doing anything else.

Record telemetry once the verifier resolves (see **Run telemetry**): `--agent verifier`.

**Step 5** — Push to remote (via the `Bash` tool):
```bash
# Prefer the configured origin and its credential helper (gh, Git Credential Manager, or SSH).
# Disable interactive prompts so a missing credential cannot hang the pipeline.
# Reuse whatever remote is configured for `origin` instead of hard-coding the URL.
if ! GIT_TERMINAL_PROMPT=0 git push origin HEAD; then
  # An explicit token is an optional non-interactive fallback, never a requirement.
  if [ -n "${GITHUB_TOKEN:-}" ]; then
    remote_url=$(git remote get-url origin)
    case "$remote_url" in
      https://*)
        remote_path=$(printf '%s' "$remote_url" | sed -e 's#^https://[^/]*@#https://#' -e 's#^https://##')
        GIT_TERMINAL_PROMPT=0 git push "https://x-access-token:${GITHUB_TOKEN}@${remote_path}" HEAD
        ;;
      *)
        echo "git push failed: origin is not an HTTPS remote and its credential helper is unavailable." >&2
        ;;
    esac
  else
    echo "git push failed: origin credentials are unavailable and GITHUB_TOKEN is not set." >&2
  fi
fi
```
If push fails → show error to user and continue to Step 6 without blocking.

**Step 6** — Docs. **Skip this step entirely when `.claude/{{PREFIX}}/config.json` sets `"docsAgent": "inert"`** — a project whose `extras/{{PREFIX}}-docs.md` makes the agent a no-op still pays a full agent spawn (body + `CLAUDE.md` + extra) to write nothing. Otherwise spawn `{{PREFIX}}-docs` (it refreshes `STATE.md`, even if `DOCUMENTATION.md`/`CLAUDE.md` need no changes):
```
SPEC: [paste]
CHANGED_FILES: [list]
Refresh STATE.md. Update DOCUMENTATION.md / CLAUDE.md only if genuinely new content (see {{PREFIX}}-docs rules).
```

---

#### TDD mode (--tdd flag, optional)

If the user passed `--tdd`, replace the default Step 1..Step 6 above with the renumbered order below. Prompt formats are identical to default mode unless noted — refer to the matching default step for the full prompt template.

**Step 1 — Tester (RED phase).** Spawn `{{PREFIX}}-tester-<platform>` with this prompt:

    red_phase=true

    Write failing unit tests (ViewModel + UseCase only) for SPEC.WHAT.
    Production code does not exist yet — that's the expected red signal.
    Return JSON per RED phase mode: {"test_files":[...], "screenshot_record_needed": false, "phase":"red", "expected_failures":[...]}

    SPEC:
    [paste SPEC block]

**Step 2 — Runner (expect red).** Run `bash .claude/scripts/{{PREFIX}}-runner-<platform>.sh false` (no screenshots in RED phase) and parse the JSON output. **Interpret the result yourself:**

- If `tests` reports failures AND `lint/detekt` is `ok` AND the failures plausibly match `expected_failures` from Step 1 → red is correct, proceed to Step 3.
- If `tests` reports `0 failed` → tester didn't actually pin a contract. Stop and ask user.
- If failures look like compile errors on the **test code itself** (not on referenced-but-not-yet-existing production classes) → tester broke syntax. Stop and ask user.

**Step 2.5 — UI Designer (pre-flight, Android only, presentation features only).** Same conditions and protocol as default-mode Step 0 (above): only fires when platform is `android` AND `SPEC.LAYERS` contains `presentation`. Spawn `{{PREFIX}}-ui-designer-android`, parse JSON, append `DESIGN_TOKENS:` to SPEC if `tokens_added` is non-empty, then proceed to Step 3.

**Step 3 — Developer (GREEN phase).** Spawn `DEVELOPER_AGENT` with this prompt:

    green_phase=true
    TEST_FILES: [list from Step 1]

    Implement production code until the listed tests are green. Do not modify the tests.
    Return JSON: {"changed_files":[...], "commit":"hash"}

    SPEC:
    [paste SPEC block]

**Step 3.5 — Reviewer.** Re-run risk routing once with the scoped CHANGED_FILES, then apply the
same deterministic + routed semantic-review sequence as default Step 1.5.

**Step 4 — Tester (default phase, second pass).** Spawn `{{PREFIX}}-tester-<platform>` again with the default Step 2 prompt and the now-implemented CHANGED_FILES. This fills in `dao`, `compose-ui`, `screenshot` (or platform analogues) tests for any test types in SPEC.TEST_TYPES that the RED phase skipped.

**Step 5 — Runner (expect green).** Same as default Step 3. From here the chain matches the default order:

- **Step 6** — Auto-fix retry (same as default Step 4).
- **Step 6.25** — Independent critic when routed (same timing as default mode).
- **Step 6.5** — Routed full Verifier (same as default Step 4.5).
- **Step 7** — Push (same as default Step 5).
- **Step 8** — Docs (same as default Step 6).
