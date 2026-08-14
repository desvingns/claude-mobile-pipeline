<!-- mp-runtime-contract: telemetry -->

## Run telemetry (fire-and-forget)

The pipeline records one structured event per significant step so the self-improvement loop
(`selfimprove/`) has real data to reflect on. After each record point below, run (via `Bash`):

At workflow start, establish one `CORRELATION_ID` (reuse a harness-provided run/workflow ID when
available; otherwise `<UTC timestamp>-mp-<mode>-<short-slug>`). Pass the same value to
every step, retry, feedback, and retro event from that workflow.

```bash
bash $MP_SCRIPTS/mp-record-run.sh --agent <step> --verdict pass|fail|partial \
  [--model <model>] [--metric "<k=v;...>"] [--retry <N>] [--note "<one line>"] \
  [--tokens-in <N>] [--tokens-out <N>] [--tokens-cached <N>] \
  [--tokens-reasoning <N>] [--cost-usd <N.N>] [--duration-ms <N>] \
  --correlation-id "$CORRELATION_ID"
```

**`--duration-ms` and `--correlation-id` are required on every record point.** Take the duration
from the wall-clock interval you actually waited on the step; never omit it because the harness did
not hand you a number. Without them the log can say a run failed but not where the hours went, and
a retro can only infer cost from timestamps that stop at the step boundary — which is how a
multi-hour run gets blamed on the build system when it was spent in review cycles. A record missing
either field is a defect in the orchestration, not an acceptable partial record.

Record points (one call each, regardless of verdict):

| step (`--agent`) | when | verdict / metric |
|---|---|---|
| `developer` | after each Developer call, including the one allowed auto-fix | payload validity/result; `tier=<standard|powerful>;purpose=<implement|autofix|repair>`; on a semantic repair also `repair_cycle=<N>;finding_ids=<ID,ID>` |
| `reviewer` | after the reviewer step resolves (script or agent fallback) | from `pass`; `violations=<N>`; add `warnings=<N>` in warn-only mode |
| `semantic-reviewer` | after the routed semantic pass | from `pass`; `findings=<N>;risk=<risk>;repair_cycle=<N>`; add `finding_ids=<ID,ID>` when findings exist, and `route_escalated=1` when the ratchet fired |
| `critic` | after the independent fresh-evidence pass, when routed | from `pass`; `findings=<N>;risk=<risk>` |
| `runner`   | after each runner outcome, scoped and full | from `pass`; `mode=<scoped\|full>;tests=<...>;lint=<ok\|fail>`; `--retry 1` when the auto-fix retry ran |
| `verifier` | after the verifier step resolves | from `pass`; `checks=<N failed or ok>` |
| `fit`      | after `--fit` Phase 3 parses the `=== FIT ===` block | `pass` when no unexplained divergences, else `partial`; `fit=<overall_score>` |
| `feedback` | the post-ship feedback question (see **Post-ship** below) | `score=<1-5>` |

Prefer provider/harness-reported input, output, cached, reasoning-token, USD-cost, and duration
values. If provider token counts are unavailable, a `characters / 4` fallback is allowed only
with `tokens_source=estimated-char4` appended to `--metric`; never present it as measured.
Omit unknown fields. `--cost` remains a legacy free-text input only—new records use
`--cost-usd`.

Telemetry is **fire-and-forget**: it must never block, fail, or retry the pipeline. If the script
is missing or errors, continue silently. Parse its single JSON line only to read `retro_due`:
when any call returns `"retro_due":true`, after the current workflow finishes offer ONCE —
"N runs since the last retro — run `bash $MP_SCRIPTS/mp-retro.sh` now? (y/N)".
On `y`, run it and show the retro path + the per-agent pass-rate table from the file.
