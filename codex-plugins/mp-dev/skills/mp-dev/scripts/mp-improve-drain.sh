#!/usr/bin/env bash
# mp-improve-drain.sh — batch ALL queued proposals in <mp_repo>/.ai/proposals/*.patch into
# ONE PR against the mobile-pipeline marketplace. Cross-platform bash; emits one JSON line.
# Queued proposals are staged by mp-improve / mp-reflect. A directly-entered
# improvement (`/mp --improve "<note>"`) goes through the single-PR path
# (mp-propose-improvement.sh) instead, so it stays a SEPARATE PR.
#
# Usage:
#   mp-improve-drain.sh <mp_repo>
#   mp-improve-drain.sh <mp_repo> --reject <slug> --reason <text>
#   mp-improve-drain.sh <mp_repo> --archive-applied <slug> --reason <text>
set -uo pipefail
MP="${1:-}"
emit() { printf '%s\n' "$1"; exit 0; }
esc() { printf '%s' "$1" | tr -d '\r\n' | sed 's/\\/\\\\/g; s/"/\\"/g'; }
[ -n "$MP" ] && [ -d "$MP/.git" ] || emit '{"ok":false,"error":"usage: <mp_repo> (a git repo)"}'
shift
cd "$MP" || emit '{"ok":false,"error":"cd failed"}'
PROP=".ai/proposals"
mode=drain; lifecycle_slug=""; lifecycle_reason=""
while [ $# -gt 0 ]; do
  case "$1" in
    --reject) mode=rejected; lifecycle_slug="${2-}"; shift 2 2>/dev/null || shift ;;
    --archive-applied) mode=applied; lifecycle_slug="${2-}"; shift 2 2>/dev/null || shift ;;
    --reason) lifecycle_reason="${2-}"; shift 2 2>/dev/null || shift ;;
    *) emit "{\"ok\":false,\"error\":\"unknown arg: $(esc "$1")\"}" ;;
  esac
done

archive_one() {
  slug="$1"; outcome="$2"; reason="$3"; stamp="$4"
  dest="$PROP/archive/$outcome/$stamp"
  [ -f "$PROP/$slug.patch" ] || emit "{\"ok\":false,\"error\":\"queued proposal not found: $(esc "$slug")\"}"
  mkdir -p "$dest" || emit "{\"ok\":false,\"error\":\"cannot create archive: $(esc "$dest")\"}"
  for ext in patch changelog md meta; do
    if [ -f "$PROP/$slug.$ext" ]; then
      mv "$PROP/$slug.$ext" "$dest/" \
        || emit "{\"ok\":false,\"error\":\"cannot archive $(esc "$PROP/$slug.$ext")\"}"
    fi
  done
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '{"proposal":"%s","status":"archived","outcome":"%s","reason":"%s","archived_at":"%s","transitions":["queued","%s","archived"]}\n' \
    "$(esc "$slug")" "$(esc "$outcome")" "$(esc "$reason")" "$now" "$(esc "$outcome")" \
    > "$dest/$slug.lifecycle.json" \
    || emit "{\"ok\":false,\"error\":\"cannot write lifecycle receipt for $(esc "$slug")\"}"
  ARCHIVE_DEST="$dest"
}

if [ "$mode" != drain ]; then
  [ -n "$lifecycle_slug" ] || emit '{"ok":false,"error":"proposal slug is required"}'
  [ -n "$lifecycle_reason" ] || emit '{"ok":false,"error":"--reason is required"}'
  lifecycle_stamp="$(date -u +%Y%m%d-%H%M%S)"
  archive_one "$lifecycle_slug" "$mode" "$lifecycle_reason" "$lifecycle_stamp"
  emit "{\"ok\":true,\"proposal\":\"$(esc "$lifecycle_slug")\",\"status\":\"archived\",\"outcome\":\"$mode\",\"archive\":\"$(esc "$ARCHIVE_DEST")\"}"
fi

shopt -s nullglob
patches=( "$PROP"/*.patch )
[ "${#patches[@]}" -gt 0 ] || emit '{"ok":true,"drained":0,"note":"no queued proposals in .ai/proposals/"}'

[ -z "$(git status --porcelain 2>/dev/null)" ] \
  || emit '{"ok":false,"error":"mobile-pipeline worktree must be clean before draining proposals"}'

BASE=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')
[ -n "$BASE" ] || BASE=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)
STAMP=$(date -u +%Y%m%d-%H%M%S)
BR="improve/batch-$STAMP"

# pre-check every patch applies against current templates/ before touching anything
for p in "${patches[@]}"; do
  git apply --check "$p" 2>/dev/null || emit "{\"ok\":false,\"error\":\"patch does not apply cleanly: $p — rebase the queue\"}"
done

git switch -c "$BR" "$BASE" 2>/dev/null || git switch "$BR" 2>/dev/null || emit "{\"ok\":false,\"error\":\"could not create branch $BR\"}"

body="Batch improvement PR — aggregates the queued proposals below into one review."$'\n'
n=0
for p in "${patches[@]}"; do
  slug="$(basename "$p" .patch)"
  git apply "$p" || emit "{\"ok\":false,\"error\":\"apply failed mid-batch: $p\"}"
  cl="$PROP/$slug.changelog"
  if [ -f "$cl" ] && [ -f .ai/changes/agent-skill-log.md ]; then
    entry_id="$(sed -n 's/^##[[:space:]]*//p' "$cl" | head -1)"
    if [ -z "$entry_id" ] || ! grep -Fqx "## $entry_id" .ai/changes/agent-skill-log.md; then
      printf '\n' >> .ai/changes/agent-skill-log.md
      cat "$cl" >> .ai/changes/agent-skill-log.md
    fi
  fi
  sumline=""; [ -f "$PROP/$slug.md" ] && sumline=" — $(head -n1 "$PROP/$slug.md")"
  body+="- ${slug}${sumline}"$'\n'
  n=$((n+1))
done

# Regenerate the committed plugin trees once for the whole batch. A failed
# generator must stop before queued → applied: the proposal files stay queued,
# while the branch/worktree preserves the applied patch as recovery evidence.
if [ -x lib/build-marketplace.sh ] && ! ./lib/build-marketplace.sh >/dev/null 2>&1; then
  emit "{\"ok\":false,\"error\":\"marketplace regeneration failed; proposals remain queued\",\"branch\":\"$(esc "$BR")\",\"applied_patches\":$n}"
fi

# queued → applied → archived, with a durable lifecycle receipt
for p in "${patches[@]}"; do
  slug="$(basename "$p" .patch)"
  archive_one "$slug" applied "included in batch branch $BR" "$STAMP"
done

git add -A
git commit -q -m "improve(batch): $STAMP — $n queued proposal(s)" -m "$body" \
  -m "Co-Authored-By: Claude <noreply@anthropic.com>" 2>/dev/null \
  || emit '{"ok":false,"error":"nothing to commit (patches produced no change?)"}'

PUSHED=false
RP=$(git remote get-url origin 2>/dev/null | sed -e 's#^https://[^/]*@#https://#' -e 's#^https://##')
if [ -n "${GITHUB_TOKEN:-}" ] && [ -n "$RP" ]; then
  git push "https://x-access-token:${GITHUB_TOKEN}@${RP}" "HEAD:refs/heads/$BR" >/dev/null 2>&1 && PUSHED=true
fi
[ "$PUSHED" = true ] || { git push -u origin "$BR" >/dev/null 2>&1 && PUSHED=true; }

PR_URL=""
if [ "$PUSHED" = true ] && command -v gh >/dev/null 2>&1; then
  PR_URL=$(gh pr create --base "$BASE" --head "$BR" --title "improve(batch): $STAMP ($n proposals)" --body "$body" 2>/dev/null | tail -n1)
fi
emit "{\"ok\":true,\"branch\":\"$BR\",\"base\":\"$BASE\",\"drained\":$n,\"pushed\":$PUSHED,\"pr_url\":\"$PR_URL\"}"
