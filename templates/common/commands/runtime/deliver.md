<!-- mp-runtime-mode: deliver -->
<!-- mp-runtime-contracts: startup execution rules -->

## Workflow: --deliver  (send a build to yourself over Telegram)

Ship the just-built artifact to your own Telegram (Saved Messages by default) via an MTProto
**user** session — so the file cap is 2 GB, not the bot API's 50 MB. No bot, no local Bot API server.

**One-time setup (out of band, not part of any pipeline run):**
1. Get `api_id` + `api_hash` at https://my.telegram.org → "API development tools".
2. Mint a session string: `bash .claude/scripts/{{PREFIX}}-deliver-telegram.sh --login`
   (prompts for phone → login code → 2FA password if set; prints a `StringSession`).
3. Put the three secrets in a **gitignored** `.env` at the repo root (or CI secrets / env):
   `TG_API_ID=…`, `TG_API_HASH=…`, `TG_SESSION=…`, optional `TG_TARGET=me` (default).
   The session string is equivalent to a login — keep it secret, never commit it.

Requires `python3` + the `telethon` package (`python3 -m pip install telethon`).

### Phase 1 — Resolve + send
Run (via `Bash`):
```bash
bash .claude/scripts/{{PREFIX}}-deliver-telegram.sh [<artifact-path>]
```
With no path it picks the newest `*.apk` under any `*/build/outputs/*`. Parse the single JSON line.

### Phase 2 — Report
On `{"ok":true,...}` print: `delivered: <file> (<mb> MB) → Telegram <target>`.
On `{"ok":false,...}` relay `error` verbatim and, when it mentions `TG_SESSION`/`telethon`/
`TG_API_*`, point the user at the one-time setup above. Never print or echo the secret values.

**Offer after a ship (epic-scoped, requires config).** Offer a delivery on the SAME timing as the
post-ship feedback question (see Post-ship → **Epic-scoped timing**), but run it BEFORE the feedback question — the user should have the app in hand before rating it: once when an epic **completes**
(its last SPEC shipped), or once when a **standalone** SPEC ships — never after a non-final slice of a
multi-SPEC epic. Only when Telegram delivery is configured (a `.env`/env at the repo root has
`TG_API_ID`). Ask EXACTLY ONCE (Claude → `AskUserQuestion`; Codex → in chat) in {{UI_LANGUAGE}}:
"Send the build to your Telegram now? (y/N)".

On **y**, first **build a fresh artifact** so the delivery includes the shipped changes, *then* send:
1. Assemble via `Bash` from the repo root — Android default: `./gradlew :app:assembleDebug` (use the
   project's standard debug-assemble task; non-Android projects use their equivalent). On a build
   failure, relay the error and **stop** — never send a stale artifact.
2. Run **Phase 1** above with no path (it auto-picks the just-built newest APK), then **Phase 2 — Report**.

Never build or send without an explicit `y` (treat no answer / anything but `y` as N). Skip silently
when Telegram is not configured.

---
