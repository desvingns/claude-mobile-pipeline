<!-- mp-runtime-mode: reflect -->
<!-- mp-runtime-contracts: startup execution rules rules-learning -->

## Workflow: --reflect  (cross-project, maintainer)

Aggregates self-improvement lessons across ALL mobile-pipeline projects and QUEUES plugin improvements
for patterns recurring in >=2 projects. Reads the global projects list
`~/.config/mobile-pipeline/projects.txt` (or `$MP_PROJECTS`).

1. Resolve `mp_repo` (as in `--improve`). Run:
   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/mp-cross-reflect.sh" "<mp_repo>"
   ```
   Parse its JSON (`digest`, `projects`, `recurring_themes`).
2. Spawn `mp-reflect` with `{digest:"<mp_repo>/<digest>", mp_repo}`. It judges the recurring
   themes and stages QUEUED proposals (opens no PRs).
3. Report `staged` / `skipped`, then: "Queued N proposal(s). Run `/mp --improve --drain` to open
   the batch PR."

---
