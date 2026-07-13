# codex-002 — system-wide token, quality, memory, and learning optimization

STATUS: complete
OWNER: codex
APPROVED: 2026-07-13 — user authorized the full implementation.

## Objective

Implement the approved audit program while preserving public `/mp` and `/mp-spec` behavior,
canonical-template ownership, cross-platform Bash, strict structured payloads, human gates, existing
dirty work, and the second-brain curated-write boundary.

## Workstreams

- Compact `/mp` router + lazy mode/shared runbooks and generated-project/plugin packaging.
- Compact `.ai` session entry point and archived handoff history.
- Safe brain inbox routing, deduplicated/compact digests, budgeted on-demand retrieval.
- Risk-based model/quality routing, verifier-lite for bugfixes, focused semantic review.
- MP Spec content-addressed cache, evidence packets, selective quality fan-out/evaluator reruns.
- Real telemetry, retro/proposal lifecycle, incremental sync, deterministic eval and CI expansion.
- Canonical-only Graphify corpus and safe rebuild/update path.

## Acceptance

- Fixed `/mp` router is materially smaller and every prior mode/flag/gate remains covered.
- Session startup reads `tasks/INDEX.md` + active tasks only; history remains retained.
- No pipeline agent can write `brain/core|domains|pipelines|projects`; candidates go to inbox.
- Telemetry captures actual-or-explicitly-estimated usage with correlation/cache fields.
- `lib/sync.sh` advances only validated adapter cursors and has fixtures.
- Applied proposals are archived, not left as a live queue and never deleted.
- Eval runner executes deterministic cases; Linux/Windows/macOS CI covers relevant seams.
- Marketplace/bootstrap regeneration, marker/placeholder checks, Bash syntax, fixtures, and graph update pass.
- VERSION, CHANGELOG, change-log, docs, task index, and handoff agree.

## Ownership during implementation

- `modular_mp_context`: canonical command/runbook packaging only.
- `brain_memory_integration`: knowledge policy + brain scripts/helpers only.
- `infra_learning_sync`: sync/telemetry/proposals/eval/CI only.
- root codex: MP Spec, risk/model routing, Graphify, bootstrap seam, integration/release.

## Validation

- Fixed router: 3.4 KB; lazy runtime: 15 runbooks / 14 contracts; generated packaging parity passes.
- Repository suites, 50-case render fuzz, 3/3 eval, Bash syntax, structured-data parsing, bootstrap
  smoke, marketplace idempotence, leak scans, and canonical Graphify rebuild pass.
- Second-brain integration preserves curated-write boundaries and reduces the due digest from about
  14.5k to about 557 estimated tokens (96.1% smaller), with raw detail available on demand.

## Residual external validation

- Real-device crawl Phases 2-4 require a reachable throwaway AVD and reference APK; this host has no
  `adb` or `emulator` command.
- Statistical model threshold tuning intentionally waits for accumulated real eval/telemetry runs.
- Local shellcheck is unavailable; the Linux/macOS/Windows CI matrix contains the authoritative gate.
