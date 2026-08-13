<!-- mp-runtime-contract: risk-routing -->

## Risk-based model and quality routing

Apply this contract before the first Developer call in `--feature`, `--phase`, or `--bugfix`.

### Prepare the routing input

Set `TASK` to `feature` or `bugfix`. Resolve an existing `SPEC_FILE`:

- backlog mode: use the active SPEC markdown file;
- phase-generated or inline feature/bugfix: persist the approved SPEC block to
  `.ai/local/mp-current-spec.md` (operational, git-ignored context; never application
  source) and use that path.

Run through Bash:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/mp-risk-route.sh" \
  --task feature|bugfix \
  --spec "$SPEC_FILE" \
  [--visual] \
  [--changed "$path"]...
```

Add `--visual` for clone/UI/fit/manifest or explicitly visual/device work. Before the first
Developer call omit `--changed`; after implementation, run the router exactly once more with one
repeatable `--changed` argument per file in the scoped task diff.

Parse its one JSON line:

```json
{
  "risk": "...",
  "developer_tier": "standard|powerful",
  "semantic_review": true,
  "verifier": "lite|full",
  "independent_critic": false
}
```

Do not require `jq`. If the script is absent, errors, or returns invalid/unknown fields, use the
safe fallback: `developer_tier=powerful`, deterministic reviewer required,
`semantic_review=true`, `verifier=full`, and `independent_critic=true`.

### Resolve agents

For Android:

- `developer_tier=standard` → `DEVELOPER_AGENT=mp-developer-standard-android`;
- `developer_tier=powerful` → `DEVELOPER_AGENT=mp-developer-android`;
- `verifier=lite` → `VERIFIER_AGENT=mp-verifier-lite-android`;
- `verifier=full` → `VERIFIER_AGENT=mp-verifier-android`.

Feature work always uses the full verifier even if a malformed/custom route says lite. A bugfix may
use lite only on the router's low-risk path; every other bugfix uses full. For a platform without
the routed aliases, use its canonical powerful Developer and full Verifier.

Use `DEVELOPER_AGENT` for the initial implementation, TDD green phase, and the single auto-fix
retry. The post-implementation router result replaces the initial aliases before later steps.

### Semantic review and independent critic

After the deterministic reviewer passes, when `semantic_review=true`, spawn
`mp-semantic-reviewer-android` with the approved SPEC file, scoped changed files, and
deterministic-review evidence. The prompt must require `pass`, `findings[]`, and `uncertainties[]`.
Every finding keeps the existing `severity`, `file`, `line`, `rule`, `evidence`, and `fix` fields.
For every `severity:"blocker"`, also require non-empty `explanation`, `user_case`, `impact`, and
`blocking_reason` fields; the blocker must be independently understandable without source-code
context, and `fix` must state the exact correction direction. Warnings may use the compact
technical format.

Validate this conditional blocker contract before continuing. A blocker missing any required
context field is an invalid semantic-review response and gets the standard one retry from
`contract-execution.md`; if the retry is still invalid, stop and surface the contract failure.
A semantic failure blocks Tester/Runner. When surfacing it, render every blocker as a
self-contained report containing, in order: plain-language explanation, Given/When/Then (or
equivalent) user case, user/business impact, why it blocks shipping, exact correction direction,
then the original technical evidence (`file`, `line`, `rule`, `evidence`, `fix`) without omission or
paraphrase. Pass the whole original payload forward as evidence. These requirements apply to the
initial semantic review and the independent critic.

When `independent_critic=true`, after the final Runner result and before Verifier run one
additional semantic-reviewer pass with a fresh evidence packet containing only the SPEC, file
paths/hashes, scoped diff, and deterministic test/review artifacts—never the first semantic
reviewer's conclusion. A critic failure blocks the chain.
Validate each structured response under `contract-execution.md`; no semantic pass may auto-fix code.
