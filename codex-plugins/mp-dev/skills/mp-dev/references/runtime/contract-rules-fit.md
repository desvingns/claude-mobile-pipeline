<!-- mp-runtime-contract: rules-fit -->

## Rules (fit gate)

- `--fit` is Android + clone-only: it captures built screens, compares them against reference images via `mp-fit-android` (read-only, multimodal), and writes divergence SPECs to `.claude/specs/backlog/` ONLY behind a y/d/n gate (same write-boundary as `--plan`). It honours `spec/deviations.md` — intended deviations are acknowledged, not filed — and flags behavioural divergences (gestures, entry order, transitions) as `behavioural_unverified` for the acceptance/feature arm rather than asserting them from a static image. Never weakens a comparison; never pushes.
- `--fit` enforces `fit_threshold` (config `fitThreshold`, default 85): the gate FAILs — and the clone may not be declared done — while the overall score is below it or any unexplained divergence remains. `--phase` auto-runs `--check` when a phase completes and (on clones) offers `--fit`.
