#!/usr/bin/env bash
# mp-propose-improvement.sh — open a PR against the mobile-pipeline marketplace with an
# improvement that mp-improve staged (a patch against templates/ + a change-log entry).
# Cross-platform bash. Emits exactly one JSON line on stdout. Run ONLY after the user approved the
# proposal in /mp --improve (this script does the branch → apply → regenerate → push → PR).
#
# Usage: mp-propose-improvement.sh <mp_repo> <slug> <patch_file_rel> <changelog_file_rel>
set -uo pipefail
MP="${1:-}"; SLUG="${2:-}"; PATCH_REL="${3:-}"; CL_REL="${4:-}"
emit() { printf '%s\n' "$1"; exit 0; }
[ -n "$MP" ] && [ -n "$SLUG" ] && [ -n "$PATCH_REL" ] || emit '{"ok":false,"error":"usage: <mp_repo> <slug> <patch_rel> <changelog_rel>"}'
[ -d "$MP/.git" ] || emit "{\"ok\":false,\"error\":\"not a git repo: $MP\"}"
cd "$MP" || emit '{"ok":false,"error":"cd failed"}'
[ -f "$PATCH_REL" ] || emit "{\"ok\":false,\"error\":\"patch not found: $PATCH_REL\"}"

# base = remote default branch, else current
BASE=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')
[ -n "$BASE" ] || BASE=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)
BR="improve/$SLUG"

git apply --check "$PATCH_REL" 2>/dev/null || emit '{"ok":false,"error":"patch does not apply cleanly against current templates/"}'
git switch -c "$BR" "$BASE" 2>/dev/null || git switch "$BR" 2>/dev/null || emit "{\"ok\":false,\"error\":\"could not create branch $BR\"}"
git apply "$PATCH_REL" || emit '{"ok":false,"error":"git apply failed after switch"}'

# append the change-log entry (append-only journal)
if [ -f "$CL_REL" ] && [ -f .ai/changes/agent-skill-log.md ]; then
  printf '\n' >> .ai/changes/agent-skill-log.md
  cat "$CL_REL" >> .ai/changes/agent-skill-log.md
fi

# regenerate the committed plugin trees from the edited templates/
[ -x lib/build-marketplace.sh ] && ./lib/build-marketplace.sh >/dev/null 2>&1

git add -A
git commit -q -m "improve: $SLUG" -m "Improvement proposed from a downstream /mp --improve session; templates/ edited + plugin trees regenerated." -m "Co-Authored-By: Claude <noreply@anthropic.com>" 2>/dev/null \
  || emit '{"ok":false,"error":"nothing to commit (patch produced no change?)"}'

# push: prefer GITHUB_TOKEN URL (non-interactive), else plain origin
PUSHED=false
RP=$(git remote get-url origin 2>/dev/null | sed -e 's#^https://[^/]*@#https://#' -e 's#^https://##')
if [ -n "${GITHUB_TOKEN:-}" ] && [ -n "$RP" ]; then
  git push "https://x-access-token:${GITHUB_TOKEN}@${RP}" "HEAD:refs/heads/$BR" >/dev/null 2>&1 && PUSHED=true
fi
[ "$PUSHED" = true ] || git push -u origin "$BR" >/dev/null 2>&1 && PUSHED=true

# open PR via gh if available
PR_URL=""
if [ "$PUSHED" = true ] && command -v gh >/dev/null 2>&1; then
  PR_URL=$(gh pr create --base "$BASE" --head "$BR" \
      --title "improve: $SLUG" \
      --body "Automated improvement proposal from a downstream \`/mp --improve\` session. Edits \`templates/\` and regenerates the plugin trees. Staged artifacts: \`.ai/proposals/$SLUG.*\`. Review before merge." 2>/dev/null | tail -n1)
fi

emit "{\"ok\":true,\"branch\":\"$BR\",\"base\":\"$BASE\",\"pushed\":$PUSHED,\"pr_url\":\"$PR_URL\"}"
