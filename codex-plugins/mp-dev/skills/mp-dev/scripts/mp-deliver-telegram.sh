#!/usr/bin/env bash
# mp-deliver-telegram.sh — send a built artifact to yourself over Telegram (MTProto).
#
# Uses a Telegram USER session (Telethon / MTProto), NOT a bot — so the file-size cap is 2 GB
# (4 GB with Premium), not the bot API's 50 MB. The default target is "me" (Saved Messages),
# i.e. you send the build to your own account. No bot, no local Bot API server.
#
# Cross-platform Bash. The MTProto call itself is delegated to python3 + the `telethon` package
# (there is no portable bash MTProto client); python3 is an external dependency like adb/gradle.
#
# Secrets are read from the environment (or a repo-root `.env`, TG_* keys only — never executed):
#   TG_API_ID    — from https://my.telegram.org → "API development tools"   (required)
#   TG_API_HASH  — from the same page                                        (required)
#   TG_SESSION   — a Telethon StringSession (mint once with `--login`)       (required to send)
#   TG_TARGET    — peer to send to: "me" (default), @username, or a numeric id   (optional)
#
# Usage:
#   mp-deliver-telegram.sh [<artifact-path>] [--caption "<text>"] [--target <peer>]
#       Send <artifact-path> (default: newest *.apk under */build/outputs/*) to TG_TARGET.
#   mp-deliver-telegram.sh --login
#       One-time interactive setup: log in by phone, print a StringSession to put in TG_SESSION.
#   mp-deliver-telegram.sh --help
#
# Output (send mode): exactly one JSON line on stdout, e.g.
#   {"ok":true,"target":"me","file":"app-release.apk","bytes":12345678,"mb":"11.8"}
#   {"ok":false,"error":"TG_SESSION not set — run with --login first"}
# Exit code mirrors "ok" (0 on success, 1 on failure) so CI can branch on it.
set -u

emit()  { printf '%s\n' "$1"; exit "${2:-0}"; }
fail()  { emit "{\"ok\":false,\"error\":\"$(esc "$1")\"}" 1; }
esc()   { printf '%s' "$1" | tr -d '\r\n' | sed 's/\\/\\\\/g; s/"/\\"/g'; }

MODE="send"; ARTIFACT=""; CAPTION=""; TARGET_ARG=""
while [ $# -gt 0 ]; do
  case "$1" in
    --login)     MODE="login" ;;
    --caption)   CAPTION="${2-}"; shift ;;
    --target)    TARGET_ARG="${2-}"; shift ;;
    -h|--help)   sed -n '2,33p' "$0"; exit 0 ;;
    --*)         fail "unknown arg: $1" ;;
    *)           [ -z "$ARTIFACT" ] && ARTIFACT="$1" || fail "unexpected arg: $1" ;;
  esac
  shift
done

# ----- python interpreter ------------------------------------------------
PYBIN=""
for c in python3 python; do command -v "$c" >/dev/null 2>&1 && { PYBIN="$c"; break; }; done
[ -n "$PYBIN" ] || fail "python3 not found (needed for the Telethon MTProto client)"
"$PYBIN" -c 'import telethon' 2>/dev/null || fail "python package 'telethon' not installed — run: $PYBIN -m pip install telethon"

# ----- load TG_* from .env (repo root) if not already in the environment --
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
ENV_FILE="$REPO_ROOT/.env"
load_env_var() {
  name="$1"; eval "cur=\${$name:-}"
  if [ -z "$cur" ] && [ -f "$ENV_FILE" ]; then
    val="$(grep -E "^[[:space:]]*${name}=" "$ENV_FILE" 2>/dev/null | head -1 \
           | sed -E "s/^[[:space:]]*${name}=//; s/^[\"']//; s/[\"']\$//")"
    [ -n "$val" ] && export "$name=$val"
  fi
}
for v in TG_API_ID TG_API_HASH TG_SESSION TG_TARGET; do load_env_var "$v"; done

[ -n "${TG_API_ID:-}" ]   || fail "TG_API_ID not set (get it at https://my.telegram.org)"
[ -n "${TG_API_HASH:-}" ] || fail "TG_API_HASH not set (get it at https://my.telegram.org)"

# ----- embed the Telethon helper (written to a temp file, then run) -------
PYFILE="$(mktemp)"; trap 'rm -f "$PYFILE"' EXIT
cat > "$PYFILE" <<'PY'
import json, os, sys
from telethon.sync import TelegramClient
from telethon.sessions import StringSession

api_id   = int(os.environ["TG_API_ID"])
api_hash = os.environ["TG_API_HASH"]
mode     = sys.argv[1]

if mode == "login":
    # Interactive: prompts for phone, the login code Telegram sends, and 2FA password if set.
    with TelegramClient(StringSession(), api_id, api_hash) as client:
        s = client.session.save()
    sys.stderr.write(
        "\n=== Telegram StringSession (store as TG_SESSION; keep it secret) ===\n"
        + s + "\n===================================================================\n"
        "Add to your .env (gitignored) or CI secrets:\n  TG_SESSION=" + s + "\n\n")
    print(json.dumps({"ok": True, "mode": "login"}))
    sys.exit(0)

# --- send mode ---
session = os.environ.get("TG_SESSION", "")
if not session:
    print(json.dumps({"ok": False, "error": "TG_SESSION not set — run with --login first"}))
    sys.exit(1)

path    = sys.argv[2]
caption = sys.argv[3]
target  = os.environ.get("TG_TARGET") or "me"
if target in ("self", ""):
    target = "me"
try:
    entity = int(target)            # numeric peer id
except ValueError:
    entity = target                 # "me", @username, phone, etc.

client = TelegramClient(StringSession(session), api_id, api_hash)
client.connect()
if not client.is_user_authorized():
    print(json.dumps({"ok": False, "error": "session not authorized — re-run --login"}))
    sys.exit(1)
try:
    client.send_file(entity, path, caption=caption or None, force_document=True)
finally:
    client.disconnect()

size = os.path.getsize(path)
print(json.dumps({
    "ok": True,
    "target": str(target),
    "file": os.path.basename(path),
    "bytes": size,
    "mb": "%.1f" % (size / 1048576.0),
}))
PY

# ----- login mode --------------------------------------------------------
if [ "$MODE" = "login" ]; then
  out="$("$PYBIN" "$PYFILE" login)" || fail "login failed (see messages above)"
  emit "$out" 0
fi

# ----- send mode: resolve the artifact -----------------------------------
[ -n "$TARGET_ARG" ] && export TG_TARGET="$TARGET_ARG"
if [ -z "$ARTIFACT" ]; then
  # newest app *.apk under any */build/outputs/*, excluding instrumentation test APKs
  # (androidTest APKs are newer than the app APK when connectedAndroidTest ran last)
  ARTIFACT="$(find "$REPO_ROOT" -type f -name '*.apk' 2>/dev/null \
              | grep '/build/outputs/' \
              | grep -v -i 'androidTest\|/androidTest/' \
              | tr '\n' '\0' | xargs -0 ls -t 2>/dev/null | head -1)"
  [ -n "$ARTIFACT" ] || fail "no artifact given and no app *.apk found under */build/outputs/ — pass a path"
fi
[ -f "$ARTIFACT" ] || fail "artifact not found: $ARTIFACT"

# default caption: filename + short commit when in a git repo
if [ -z "$CAPTION" ]; then
  CAPTION="$(basename "$ARTIFACT")"
  sha="$(git rev-parse --short HEAD 2>/dev/null || true)"
  [ -n "$sha" ] && CAPTION="$CAPTION @ $sha"
fi

# size sanity (MTProto user-session cap is 2 GB / 4 GB Premium)
bytes="$(wc -c < "$ARTIFACT" 2>/dev/null | tr -d ' ')"
case "$bytes" in ''|*[!0-9]*) bytes=0 ;; esac
if [ "$bytes" -gt 2147483648 ]; then
  fail "artifact is $((bytes/1048576)) MB — over the 2 GB MTProto limit"
fi

out="$("$PYBIN" "$PYFILE" send "$ARTIFACT" "$CAPTION")" || fail "telethon send failed"
# relay python's single JSON line; mirror ok→exit code for CI
case "$out" in
  *'"ok": true'*|*'"ok":true'*) emit "$out" 0 ;;
  *) emit "$out" 1 ;;
esac
