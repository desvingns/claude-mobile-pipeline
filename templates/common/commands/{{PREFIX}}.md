Senior mobile developer for the {{PROJECT_NAME}} repository. Use for ALL {{PROJECT_NAME}} tasks.

This command is a compact router. The detailed workflow is loaded lazily from the canonical
runtime tree; do not preload the other modes.

**Cross-platform invariant.** Any shell command in this pipeline runs through Bash (Git Bash on
Windows, native bash on Linux/macOS), never PowerShell. Resolve repository paths dynamically.

## Runtime resolution

Resolve `RUNTIME_ROOT` to the first available location:

1. `${MP_RUNTIME_ROOT}`, only when the harness explicitly provides it.
2. `${CLAUDE_PLUGIN_ROOT}/commands/{{PREFIX}}-runtime` for the Claude plugin.
3. `{{AGENT_DIR}}/commands/{{PREFIX}}-runtime` for a generated project.
4. The directory containing this router for the Codex bridge's packaged
   `skills/mp-dev/references/runtime/router.md`.

If no candidate contains `manifest.tsv`, stop and report the missing runtime package. Never guess
a workflow from memory.

## Lazy-loading protocol

1. Parse the user's selector using the table below. Sub-flags never select a second mode:
   `--tdd`, `--next`, `--chain`, and `--backlog` belong to `feature`; `--phases`, `--bootstrap`,
   `--sync`, and `--from` belong to `plan`; `--drain` belongs to `improve`.
2. If no selector is present, ask whether this is a feature, bug, or brainstorm; do not load a
   runbook until the answer selects one mode.
3. Read exactly one `<mode>.md` from `RUNTIME_ROOT`.
4. Parse its first `<!-- mp-runtime-contracts: ... -->` line and read exactly those
   `contract-<name>.md` files, once each. Do not read `manifest.tsv`, another runbook, or an
   undeclared contract.
5. Execute `contract-startup.md` first, then the selected runbook. Shared contracts are binding;
   the selected runbook wins only where it is explicitly more specific.
6. A gated transition started by `--continue` is a new dispatch after the user accepts it. The
   `--phase` runbook already declares the shared feature-implementation contract and must not load
   `feature.md`.

## Mode dispatch

| Selector | Runbook | Important sub-flags / arguments |
|---|---|---|
| `--feature` | `feature.md` | `--tdd`, `--next`, `--next --chain`, `--backlog <slug>`, or free-text description |
| `--bugfix` | `bugfix.md` | broken-behaviour description |
| `--discuss` | `discuss.md` | read-only topic brainstorm |
| `--spec` | `spec.md` | backlog-only authoring, no implementation |
| `--coverage` | `coverage.md` | optional scope and `--target=N`; Android only |
| `--upgrade` | `upgrade.md` | optional comma-separated model IDs |
| `--device` | `device.md` | one screen/scope; Android only |
| `--fit` | `fit.md` | optional screen/scope; Android clone comparison gate |
| `--plan` | `plan.md` | `--from <bundle|tdd>`; `--phases [--bootstrap|--sync|--phase NN]` |
| `--phase` | `phase.md` | one next task from the active numbered phase |
| `--check` | `check.md` | read-only phase/anchor validator |
| `--continue` | `continue.md` | gated recommendation of one next workflow |
| `--improve` | `improve.md` | direct note or `--drain`; plugin changes only through a gated PR |
| `--reflect` | `reflect.md` | cross-project reflection and queued proposals |
| `--deliver` | `deliver.md` | optional artifact path or one-time `--login` setup |

Unknown or conflicting primary selectors are an error: show this table and ask the user to choose
one. Preserve every human gate, structured payload, retry limit, write boundary, and report shape
defined by the loaded files.

**`--chain` is a strict feature modifier.** It is valid only in the exact combination
`--feature --next --chain`; reject it with any other primary selector, with `--backlog`, or without
`--next`. It never changes which SPEC `--next` resolves. Its only effect is a Codex-only hand-off
after a successful SPEC close, as defined by the selected `feature.md` and post-ship contract.

**`--unattended`** is a modifier, not a mode: it may accompany any selector above and declares that
nobody is watching. Advisory gates then proceed on their recommended default and are reported in a
"decisions taken while unattended" summary at the end (see `contract-risk-routing.md`). The exact
`--feature --next --chain` modifier is a scoped exception: it authorizes the just-completed SPEC's
close-out push and one Codex successor hand-off. That exception does not authorize unrelated
pushes or other external side effects. All other destructive or outward-pushing gates — SPEC
approval, `git push`, anything the user is asked to confirm elsewhere — still stop and wait. Use
`--unattended` for overnight or background runs. Natural-language instructions such as "skip all human gates", "пропускай все human gate", "do this without asking", or "run unattended" declare the same unattended policy. Preserve it in a
`--chain` successor prompt, but do not infer unattended from `--chain` alone.
