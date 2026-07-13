# Second-brain integration

The generated mobile pipeline treats `D:/Pet/brain` as a shared, human-curated
knowledge layer. Project memory remains authoritative for project-only facts.

## One resolver, asymmetric permissions

`templates/common/scripts/{{PREFIX}}-brain-memory.sh` is the only supported gateway
for an MP agent. It resolves, in order, an explicit `--brain`, `$BRAIN`,
`~/.config/brain/root`, and the personal-machine/VM defaults. It may read an
existing `$MP_USER_PROFILE`, `brain/core/user-profile.md`, or the legacy local
profile, but every resolved profile is read-only.

At startup the orchestrator calls this resolver once, reads only the returned profile path,
and requests a 600-token tagged context only when non-core knowledge can materially affect the
task. If the gateway is unavailable, it retains the legacy profile fallback but never scans the
brain directly. Routine work therefore pays no non-core retrieval cost.

The write policy is deliberately asymmetric:

| Data | Read | Agent write |
|---|---|---|
| project `.ai/memory/` and `.claude/mp/extras/` | on demand | allowed |
| `$MP_USER_PROFILE` / `brain/core/*` | on demand | forbidden |
| `brain/domains|pipelines|projects/*` | tag-selected | forbidden |
| `brain/inbox/*` | dedupe lookup | gateway append only |

USER-PREFERENCE and BRAIN-LEVEL lessons therefore use `append-candidate`. The
gateway normalizes lesson + provenance, assigns `cand-<fingerprint>`, detects retries, and
appends a provenance-rich `status: NEW` block. `suggested_file` is metadata, never
a write target. `/brain promote` remains the only route into curated files.

An optional local exclusion policy may be supplied through `BRAIN_EXCLUDE_RE` or one ERE per
line in `${BRAIN_EXCLUDE_FILE:-~/.config/brain/exclude-pattern.txt}`. The policy is machine-local;
organization-specific terms never need to enter the shared personal repository.

## Token-bounded reads

`context --tags "android testing" --budget 600` matches tags against `INDEX.md`,
selects no more than three files, and emits one JSON line containing at most the
requested approximate token budget (`characters / 4`). The global cap defaults to
1600 tokens (`BRAIN_CONTEXT_MAX_TOKENS`). No match returns empty context; it never
falls back to bulk-loading the brain or a raw digest.

## Provenance and promotion receipts

Each candidate carries a stable id, kind, scope, evidence, source, capture time,
suggested target, and status. Promotion keeps the block and changes its status to
`PROMOTED -> <target>`, adding a receipt with timestamp and optional git commit.
This makes the chain traceable without putting operational history into the tiny
always-loaded core.
