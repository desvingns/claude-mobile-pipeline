<!-- mp-runtime-contract: execution -->

Senior mobile developer for the project repository. Use for ALL the project tasks.

**Cross-platform.** Runs on Linux, macOS, and Windows. All shell commands in this pipeline
MUST be executed through the `Bash` tool (Git Bash on Windows, native bash on Linux/macOS) —
never PowerShell. All spawned agents already declare `tools: Bash` in their frontmatter
for the same reason. Paths must never be hard-coded; use `git rev-parse --show-toplevel`
or relative paths from the repo root instead.

## Deterministic steps via $MP_SCRIPTS/

Two pipeline steps that used to spawn agents are now plain Bash scripts. They emit exactly
one JSON line to stdout (gradle/grep logs go to temp files) so the orchestrator's context
stays the same size as before, but skips the LLM round-trip entirely:

- `$MP_SCRIPTS/mp-runner-<platform>.sh [screenshot_record_needed]` — replaces
  `mp-runner-<platform>` agent
- `$MP_SCRIPTS/mp-reviewer-<platform>.sh <file1> <file2> ...` — replaces
  `mp-reviewer-<platform>` agent
- `$MP_SCRIPTS/mp-deliver-telegram.sh [<artifact-path>]` — send a built artifact to
  yourself over Telegram (MTProto user session); emits one JSON line. Used by `--deliver`.
- `$MP_SCRIPTS/mp-risk-route.sh --task <feature|bugfix> --spec <file> ...` —
  risk/model/quality routing; emits one JSON line. Invalid output takes the documented safe route.
- `$MP_SCRIPTS/mp-brain-memory.sh append-candidate ...` — inbox-only durable
  memory candidate routing; emits one JSON line and is always fire-and-forget.

The runner/reviewer agent files are kept as a **fallback** only: invoke them via `Agent`
when a script fails (non-zero exit, unparseable JSON, missing dependency).

## Strict output contracts for LLM agents

Every LLM agent in the chain must return exactly one structured payload as its final
message — no prose before or after, no markdown fences. The shape depends on the agent:

| Agent          | Payload         |
|----------------|-----------------|
| `mp-architect`            | One BRAINSTORM block (framed by `=== BRAINSTORM ===` markers), or one CAPSULE block in `PREFLIGHT` mode |
| `mp-developer-<platform>` | JSON `{"changed_files":[...], "commit":"hash"}`; on a semantic repair pass also `"resolved_findings":[{"id":..., "status":"fixed\|regressed\|superseded", "note":...}]` |
| `mp-developer-standard-android` | JSON `{"changed_files":[...], "commit":"hash"}` (same `resolved_findings` rule on repair) |
| `mp-tester-<platform>`    | JSON `{"test_files":[...], "screenshot_record_needed": bool, ...}` |
| `mp-verifier-<platform>`  | JSON `{"pass": bool, "static_checks":{...}, "manual_checklist":[...]}` |
| `mp-verifier-lite-android` | JSON `{"pass": bool, "static_checks":{...}, "manual_checklist":[...]}` |
| `mp-semantic-reviewer-android` | JSON `{"pass": bool, "risk":"...", "findings":[...], "uncertainties":[...], "confidence": number}`; each finding keeps `severity/file/line/rule/evidence/fix`, and a blocker additionally requires `explanation/user_case/impact/blocking_reason` |
| `mp-docs`                 | JSON `{"committed": bool, "files":[...], "commit":"hash"}` (files/commit only when committed=true) |

After every LLM agent call:

1. Extract the JSON (or BRAINSTORM block) from the agent's response.
2. Parse it. If parsing fails or required keys are missing → spawn the same agent ONE more
   time, prefixing the original prompt with:
   `Previous response was not valid JSON. Return ONLY the JSON object specified, no prose.`
   (For `mp-architect`, replace "JSON" with "BRAINSTORM block".)
3. If the retry still fails → stop the pipeline and show both responses to the user.
