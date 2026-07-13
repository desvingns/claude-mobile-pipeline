# selfimprove/ — the self-improvement loop

A closed **observe → reflect → propose → gate → propagate** loop, built on this repo's own
primitives. Principle from the architecture review: *self-improvement is a loop, not a store* —
we persist the structured signals the agents already emit, reflect on them, and route proposed
fixes through a human gate into the existing change-log → sync rail.

## Two folders, two lifetimes
- **Telemetry (raw, high-volume, gitignored):** `runs/*.jsonl` — one JSON event per agent/run,
  append-only, never hand-edited.
- **Distilled lessons (low-volume, git-tracked signal):** `lessons.md` (+ cmp's `.ai/memory/`).
  The reflection step promotes patterns here; raw telemetry never pollutes the signal.

## The loop
1. **Capture (L1):** `./record-run.sh --agent <name> --verdict pass|fail|partial [--model M]
   [--tokens-in N] [--tokens-out N] [--tokens-cached N] [--tokens-reasoning N]
   [--cost-usd N.N] [--duration-ms N] [--usage-source provider|estimated]
   [--correlation-id ID]` appends one JSON line. Unmarked legacy token/cost values are labeled
   `estimated`; use `provider` only for counters exposed by the model/runtime. Every usage field
   remains optional, so older event producers stay valid.
2. **Reflect (L2):** `./retro.sh` aggregates the JSONL → `retro/retro-<date>.md` (per-agent
   pass-rate, feedback, structured token/cost/duration totals). `./retro.sh --health` is the
   cheap dormant-telemetry check. `reflect.sh` remains the legacy entrypoint.
3. **Propose (L3):** run `REFLECTION-PROMPT.md` in Claude/Codex — or the `selfimprove-retro`
   agent — to turn the retro into concrete, minimal change proposals.
4. **Gate:** a human approves. Approved changes get one entry in `.ai/changes/agent-skill-log.md`.
5. **Propagate:** `lib/sync.sh` carries the change to the per-tool adapters — the same rail the
   dual-tool design already uses. Never hand-maintain two copies.

```
record-run.sh ──▶ runs/*.jsonl ──▶ retro.sh ──▶ retro/*.md ──▶ REFLECTION-PROMPT
      (L1)            (raw)            (L2)         (digest)            (L3)
                                                                         │ human gate
                                                                         ▼
                                              .ai/changes/agent-skill-log.md ──▶ lib/sync.sh ──▶ adapters
```

## Why on our own primitives
cmp already emits structured JSON (runner/reviewer) and has a change-log → `lib/sync.sh` rail plus
durable `.ai/memory/`. The loop just closes the open ends: persist the JSON we were throwing away,
reflect on it, and feed the rail. No external memory product required.

## Scheduling the loop (so nobody has to remember it)

Capture is automatic (the orchestrator records events fire-and-forget and offers a retro when
`retro_due` fires — roadmap stage 1). The two remaining manual seams can run on a schedule:

- **Per-project retro** — already nudged in-session (`retro_due` after ≥ `$REFLECT_AFTER`
  events). No scheduler needed.
- **Cross-project reflection (weekly)** — `/mp --reflect` needs a local harness + the projects
  on this machine, so it runs host-side, not in cloud CI. Examples:
  - Linux/macOS cron: `0 9 * * 1  cd <any-mp-project> && claude -p "/mp --reflect"`
  - Windows Task Scheduler:
    `schtasks /Create /SC WEEKLY /D MON /ST 09:00 /TN mp-reflect /TR "wsl-or-gitbash -c 'cd <any-mp-project> && claude -p \"/mp --reflect\"'"`
  - Or simply a recurring reminder to run `/mp --reflect` in any wired project; it ends by
    suggesting `/mp --improve --drain` when proposals queued up.
- **Keep the projects list fresh** — `~/.config/mobile-pipeline/projects.txt` (one repo root
  per line, Git-Bash style paths) is what cross-reflect scans. Append every newly wired/
  bootstrapped project to it as part of project setup (see docs/MARKETPLACE.md → Enable in a
  project); a stale list silently shrinks the loop.

## Relation to `eval/`
`eval/` is for **regression cases** (expected vs actual on fixed inputs). `selfimprove/` is for
**live telemetry + reflection** across real runs. The retro can nominate new `eval/` cases; the
eval gate can later block improvement PRs that regress. They are complementary.
