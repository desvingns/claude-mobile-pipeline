<!-- mp-runtime-mode: fit -->
<!-- mp-runtime-contracts: startup execution platform device telemetry backlog rules rules-board rules-implementation rules-fit -->

## Workflow: --fit  (Android clone projects — reference-comparison gate)

The clone analogue of a QA pass: capture the built app's screens, compare each against the reference
image it is meant to reproduce, and file a backlog SPEC for every UNEXPLAINED visual divergence.
Android only; meaningful only for a **clone** project (one built from a reference app via `/mp-spec`
clone mode). Skip on greenfield or iOS-only projects. This is the gate that stops a clone from
silently drifting away from its reference.

### Phase 1 — Resolve references + ensure a device

1. **Reference set + screen mapping.** Resolve, in priority order:
   a. `spec/fit/registry.csv` (screen_id → reference image → built-capture hint), if present;
   b. else `.claude/mp/config.json` `referenceScreenshotsDir` (+ optional `referenceScreenshotMap`);
   c. else ASK the user for the reference screenshots directory and how its images map to screens.
   Build the `screens[]` list of `{screen_id, name, reference}` pairs.
   Also resolve **`fit_threshold`**: `.claude/mp/config.json` → `fitThreshold` (integer 0–100);
   absent → default **85**. This is the enforced pass bar for the gate, not advice.
2. **Device gate (mandatory, same as `--device`).** Apply the **Visual autotest device pre-flight
   (Android)**, then read the `device-connection` memo and confirm with `adb devices`. If none is
   usable → STOP, ask the user how the device/emulator is connected, record the answer to the memo,
   re-check. Capture needs a booted device (unless every built screen comes from recorded
   Roborazzi/Paparazzi output — then a device is optional).

### Phase 2 — Capture the built screens

**Normalize the capture environment first** (device captures only — so the pixels measure the
app, not the chrome; mirror the profile the reference frames were captured on, recorded in the
bundle's `00_meta.yaml` → `crawl.device` when the crawl ran):
```bash
adb shell settings put global sysui_demo_allowed 1
adb shell am broadcast -a com.android.systemui.demo -e command enter
adb shell am broadcast -a com.android.systemui.demo -e command clock -e hhmm 1000
adb shell am broadcast -a com.android.systemui.demo -e command battery -e level 100 -e plugged false
adb shell am broadcast -a com.android.systemui.demo -e command network -e wifi show -e level 4
adb shell am broadcast -a com.android.systemui.demo -e command notifications -e visible false
adb shell settings put system font_scale 1.0
```
Best-effort (never block on demo mode); broadcast `-e command exit` when capture finishes. If
the reference profile (resolution/density) is known and differs from the connected device, warn
the user — pixel scores will be depressed by pure scaling.

Populate `build/fit/built/<screen_id>.png` for each screen, using the first available source:
- **Roborazzi/Paparazzi output** — if the project records Compose screenshots covering these screens,
  copy those PNGs (no device needed for that part).
- **Instrumented screen-tour** — if a screen-tour instrumented test exists, run it via
  `mp-runner-instrumented-android` and `adb pull` its PNGs.
- **adb fallback** — for each screen, navigate to it (deep-link if available, else drive the UI) and
  capture: `adb exec-out screencap -p > build/fit/built/<screen_id>.png`.
Record `built:null` for any screen you could not capture (the comparator marks it `captured:false`).

**Element-tree dumps (structural diff input).** When `spec/fit/elements/` exists AND a device is
the capture source, also dump each screen's element tree right after its screenshot:
`MSYS_NO_PATHCONV=1 adb shell uiautomator dump /sdcard/ui.xml && adb exec-out cat /sdcard/ui.xml > build/fit/built/<screen_id>.xml`
(on Git Bash keep `MSYS_NO_PATHCONV=1` — /sdcard path mangling). Best-effort: a failed dump just
means the structural diff is skipped for that screen (note it); never block the capture pass.

### Phase 2.5 — Objective pixel pass (deterministic, before the agent)

For each (screen, state) with BOTH a reference image and a built capture, run:
```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/mp-pixel-diff.sh --reference <reference.png> --built <built.png> --out build/fit/diff/<screen_id>.png
```
Parse each single JSON line; collect `pixel_scores = {screen_id: {similarity, rmse_pct, heatmap, resized}}`.
On `tool_missing` (ImageMagick absent) → tell the user once (install hint), set
`pixel_scores: unavailable`, continue — the multimodal pass still runs. The heatmaps under
`build/fit/diff/` are evidence artifacts for the report.

### Phase 3 — Compare

Spawn agent `mp-fit-android` with:
```
Compare the built screens against their reference images and return one === FIT === block per your output spec.

screens: [ {screen_id, name, reference, built} ... ]
deviations: spec/deviations.md   (omit the line if absent)
design_notes: spec/design.md     (omit the line if absent)
elements_dir: spec/fit/elements  (omit if absent — enables the structural element diff)
built_dumps: build/fit/built     (omit if no *.xml dumps were captured)
checklists: spec/fit             (omit if the bundle has no fit/<screen_id>.md checklists)
pixel_scores: <the Phase 2.5 map, or "unavailable">
epic_slug: fit
date: <today YYYY-MM-DD>
```
Parse the `=== FIT ===` block (retry ONCE with a "block only, no prose" preface on parse
failure; a second failure → stop and show the response).

Record telemetry (see **Run telemetry**): `--agent fit`, verdict `pass` when
`overall_score ≥ fit_threshold` AND there are no unexplained divergences (else `partial`),
metric `fit=<overall_score>;threshold=<fit_threshold>`.

### Phase 4 — Report + gated write

Print the per-screen `fit_score` table, the `divergences`, the `acknowledged_deviations`, and
the `behavioural_unverified` pointers.

**Taste journal.** If the block carries a non-empty `taste_signals[]` (durable cross-project
preference candidates the comparator inferred from intended deviations), show them and ask ONE
y/N: "Queue these as cross-project preference candidates?". On `y`, route each signal through
the inbox-only memory helper (one call per signal; normalize `--text` to concise English):

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/mp-brain-memory.sh" append-candidate \
  --kind user-preference \
  --project "the project" \
  --text "<durable preference, English>" \
  --evidence "the project, <date>, --fit taste journal, <report/path>" \
  --source "mp-fit-taste-journal"
```

Each call emits one JSON line and is fire-and-forget: a missing/erroring helper never blocks the
fit report. It queues or deduplicates an inbox candidate; it never writes the curated user profile
or brain core directly. Skip silently when `taste_signals` is empty.

If `proposed_specs` is non-empty, ask:
"Write N divergence SPEC(s) to `.claude/specs/backlog/`? (y / d — show bodies / n)".
- **y** → write each `proposed_specs[].rendered_markdown` to `.claude/specs/backlog/<filename>`
  verbatim; add/update a `fit-00-overview.md` index. (These are `Status: draft` board SPECs.)
- **d** → dump each body, then re-ask.
- **n** → write nothing.
Never write outside `.claude/specs/`.

### Phase 5 — Report

```
fit: <N screens compared> — overall <overall_score>/100 vs threshold <fit_threshold> → PASS | FAIL
   Pixel (SSIM/RMSE): <avg similarity>% avg | unavailable   heatmaps: build/fit/diff/
   Checklist rows: <passed>/<total> (failed rows listed per screen above)
   Filed: <M> divergence SPEC(s) → .claude/specs/backlog/ (epic: fit)
   Behavioural to verify: <K> (run the acceptance/feature arm / --device)
   Next: /mp --feature --next  (fix the top divergence), then re-run /mp --fit
```

**Threshold enforcement:** the gate result is FAIL while `overall_score < fit_threshold` OR any
unexplained divergence remains. On FAIL, say explicitly that the clone may NOT be declared done
(the Fit-gate phase stays open / the clone-done criterion is unmet) until a re-run passes.

The loop closes by implementing the filed SPECs (`--feature --next`) and re-running `--fit`
until the score meets the threshold and only intended deviations remain.

---
