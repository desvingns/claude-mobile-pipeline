<!-- mp-runtime-contract: platform -->

## Platform resolution

This project supports the following platforms (see `CLAUDE.md` → Stack section): **see `.claude/mp/config.json` `platforms:` field**.

When this project has **one** platform, agent names with `<platform>` suffix below resolve to that single platform — e.g. `mp-developer-<platform>` means `mp-developer-android` for an android-only project.

When this project has **multiple** platforms, every SPEC must include an explicit `PLATFORM: <name>` field, and orchestrator spawns the matching platform's agent for each step. If a task spans both platforms, run two SPECs sequentially (one per platform) — do not interleave.
