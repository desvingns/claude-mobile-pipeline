<!-- mp-runtime-mode: device -->
<!-- mp-runtime-contracts: startup execution platform device telemetry rules rules-implementation -->

## Workflow: --device  (Android only — one on-device instrumented-test slice)

Writes and runs ONE instrumented Compose-UI test for a single control on a connected device/emulator,
then stops. This enforces a "write one test → run on device → green → STOP" loop — deliberately small
so a less-capable model stays on rails and never batches blind. Skip on iOS-only projects (the
instrumented runner agent is Android-only).

### Phase 1 — Ensure a device is connected (mandatory) + pick the target

1. Apply the **Visual autotest device pre-flight (Android)**. **A connected device is non-negotiable — never run, or claim to run, on-device tests without one.**
   Read the connection from the `device-connection` memory memo, then confirm with `adb devices`. If
   none is listed (offline/unauthorized/empty), the wrong device is attached, or the connection was
   lost: **STOP and ask the user where/how the test device/emulator is connected now** (device,
   serial, connection method); **record their answer to the `device-connection` memo** so it is not
   asked again while it works; then re-check. Do not spawn any agent until a device is confirmed.
2. Pick the screen/scope from the argument and ONE un-covered control on it (a control with no
   instrumented test yet). One control per run.

### Phase 2 — Add a seam only if one is needed

If the control has no testable hook, spawn `{{PREFIX}}-developer-<platform>` to add **only** a
`Modifier.testTag(...)`, a `contentDescription`, or `<Name>Content` public visibility — never new UI,
events, or behaviour. Then run the reviewer (script, agent fallback). If `pass=false` → stop. If the
control genuinely does not exist in production → do not invent it; report the gap and stop.

### Phase 3 — Write ONE test

Spawn `{{PREFIX}}-tester-<platform>`:
```
Write exactly ONE instrumented Compose-UI @Test for the control below: createComposeRule, render the public <Name>Content directly inside the app theme, capture events, assert after idle. New file or one new @Test in the screen's existing *ContentUiTest. No batching. Strings via resources, not literals. Return JSON: {"test_files":[...], "screenshot_record_needed": false}

CONTROL: <control + expected event/state>
TEST CLASS: <fully-qualified test class>
```

### Phase 4 — Run it on the device

Spawn `{{PREFIX}}-runner-instrumented-android`:
```
Run this one instrumented test class on the connected device and return parsed JSON.
TEST_CLASS: <fully-qualified test class>
```

### Phase 5 — Record or recover

- **Green** (`pass=true`, `failures=0`, `skipped=0`): commit the test (`test: cover <screen>
  <control>`); any seam from Phase 2 stays in its own `feat/fix:` commit. Note coverage in your
  project's tracker / STATE.md if you keep one. **Do not push** (device slices accumulate; push per
  session).
- **Red** (`pass=false`): if it's a real defect, spawn `{{PREFIX}}-developer-<platform>` once for a
  minimal fix, then re-run the instrumented runner once. Still red → STOP, show the report. Never
  weaken the test.

### Phase 6 — Report and stop

```
device: <screen> — <control> <green N/N | red | escalated>
   Test: <FQN>::<method>
   Commit: <hash> (test) [+ <hash> seam]
   Next un-covered control: <suggestion>
```
Stop after one control. Do not start the next in the same run.

---
