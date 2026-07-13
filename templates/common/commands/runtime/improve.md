<!-- mp-runtime-mode: improve -->
<!-- mp-runtime-contracts: startup execution rules rules-learning -->

## Workflow: --improve  (improve the pipeline itself)

For a lesson that would help **every** project on the plugin (a wrong/missing rule in a generic
`mp-*` agent or this orchestrator) — NOT a project-local quirk (those go to memory / `.claude/mp/extras/`).
Opens a PR against the **mobile-pipeline** marketplace; this project's repo is never touched.

Resolve the mobile-pipeline repo path (both modes) from `.claude/settings.json` →
`extraKnownMarketplaces.mobile-pipeline.source.path` (or `$MP_REPO`).

### Mode A — Direct (your note → its OWN PR)
`/{{PREFIX}} --improve "<note>"`. A deliberate, single improvement — kept SEPARATE from the batch.
1. Spawn `{{PREFIX}}-improve` with `{problem:"<note>", target_hint, mp_repo}`; it stages a patch +
   change-log under `mp_repo/.ai/proposals/<slug>.*` and returns a `=== PROPOSAL ===` block. Relay any
   `error` (`mp_repo_unresolved`, `no_clean_patch`).
2. Show `summary`, `rationale`, `targets`, `apply_check`. Ask: "Open a PR for this one? (y/n)". On `y`:
   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/{{PREFIX}}-propose-improvement.sh" "<mp_repo>" "<slug>" "<patch_file>" "<changelog_file>"
   ```
   Parse the one JSON line. On `n` → it stays queued for a later `--drain`.

### Mode B — Drain (batch the queue → ONE PR)
`/{{PREFIX}} --improve --drain` (or `--improve` with no note). Aggregates everything auto-staged by
`{{PREFIX}}-knowledge` / `{{PREFIX}}-reflect`.
1. Count queued proposals (`mp_repo/.ai/proposals/*.patch`). None → say so and stop.
2. List slugs + summaries. Ask: "Open ONE batch PR with these N proposals? (y/n)". On `y`:
   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/{{PREFIX}}-improve-drain.sh" "<mp_repo>"
   ```
   Parse the one JSON line (`branch`, `pr_url`, `drained`).

### Report
```
improve: <direct slug | batch of N> — PR <pr_url | not opened>
   Branch: <branch> off <base>   (CI gate runs on the PR; review + merge on GitHub)
```
**Never** push to mobile-pipeline without an explicit `y`. gh absent → the script still pushes the
branch; open the PR from the printed GitHub URL.

---
