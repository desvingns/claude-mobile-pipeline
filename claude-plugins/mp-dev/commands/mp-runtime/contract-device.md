<!-- mp-runtime-contract: device -->

## Visual autotest device pre-flight (Android)

Run this hard gate before implementation/test execution for Android tasks that are explicitly visual
and require visual/device autotests. Do not apply it to every presentation-layer change; apply it when
the SPEC/task/phase mentions visual, layout, theme, animation, screenshot, fit, reference
comparison, visual QA, `screenshot`, `instrumented-compose-ui`, `--device`, `--fit`, or a phase
done-criterion that requires device-rendered visual autotests.

Read the `device-connection` memory memo, then confirm a usable booted device/emulator with
`adb devices -l`. If the project records a required AVD/device name or helper in `CLAUDE.md` or
`.claude/mp/extras/`, verify that exact device and boot state before spawning any agent. If no usable
device is present, or the wrong/offline/unauthorized device is attached, STOP immediately and ask the
user to boot/connect the required device/emulator first; record/update the `device-connection` memo
after they answer, then re-check. Use this stop message:

```
Visual autotests need a connected, booted device/emulator before this pipeline can continue. Please
start/connect <required device> first; correct development cannot proceed without visual testing.
```

Never continue blind, never replace a required device visual gate with JVM-only checks or screenshot
baselines, and never claim visual tests ran or passed without the connected-device evidence.
