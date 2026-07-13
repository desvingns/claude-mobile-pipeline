<!-- mp-runtime-contract: startup -->

## Startup

1. Read `CLAUDE.md` (at the repository root) for tech stack and architecture.
2. Read `STATE.md` to know current iteration and what's in flight.
3. Resolve shared memory once through
   `bash "{{AGENT_DIR}}/scripts/{{PREFIX}}-brain-memory.sh" resolve`. If it returns a non-empty
   `profile_read`, read that file once as READ-ONLY context. Use profile facts ONLY to bias
   recommended answers and elicitation defaults; they never auto-decide anything and absence
   changes nothing. If the gateway is absent or unavailable, preserve the read-only fallback:
   `$MP_USER_PROFILE`, then `~/.config/mobile-pipeline/user-profile.md`. Never scan `brain/`
   directly and never write any resolved profile.
4. Confirm task type. If flag missing → ask: "Это новая фича / баг / brainstorm?" (or the equivalent in {{UI_LANGUAGE}}).
5. Pull non-core brain context only when it can materially affect this task. Call
   `bash "{{AGENT_DIR}}/scripts/{{PREFIX}}-brain-memory.sh" context --tags "<2-5 specific task tags>" --budget 600 --max-files 3`
   once, consume only its bounded `context`, and do not open additional brain files directly.
   Skip this call for routine work or when profile context is sufficient; gateway failure is a
   silent no-context fallback, not a reason to bulk-load memory.

---
