#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture="$repo/tests/fixtures/proposals"
work="$(mktemp -d "${TMPDIR:-/tmp}/cmp-proposal-test.XXXXXX")"
remote="$(mktemp -d "${TMPDIR:-/tmp}/cmp-proposal-remote.XXXXXX")"

copy_lf() {
  tr -d '\r' < "$1" > "$2"
}

git init -q --bare "$remote"
git -C "$work" init -q -b main
git -C "$work" config core.autocrlf false
mkdir -p "$work/templates" "$work/.ai/proposals" "$work/.ai/changes"
printf 'before\n' > "$work/templates/demo.txt"
printf '# fixture log\n' > "$work/.ai/changes/agent-skill-log.md"
copy_lf "$fixture/change-demo.patch" "$work/.ai/proposals/change-demo.patch"
copy_lf "$fixture/change-demo.changelog" "$work/.ai/proposals/change-demo.changelog"
git -C "$work" add .
git -C "$work" -c user.name=cmp-test -c user.email=cmp@example.invalid commit -qm fixture
git -C "$work" remote add origin "$remote"
git -C "$work" push -qu origin main
git --git-dir="$remote" symbolic-ref HEAD refs/heads/main

out="$(GIT_AUTHOR_NAME=cmp-test GIT_AUTHOR_EMAIL=cmp@example.invalid \
  GIT_COMMITTER_NAME=cmp-test GIT_COMMITTER_EMAIL=cmp@example.invalid \
  bash "$repo/templates/common/scripts/{{PREFIX}}-improve-drain.sh" "$work")"
printf '%s' "$out" | grep -q '"drained":1'
grep -q '^after$' "$work/templates/demo.txt"
[ ! -f "$work/.ai/proposals/change-demo.patch" ]
receipt="$(find "$work/.ai/proposals/archive/applied" -name 'change-demo.lifecycle.json' -print | head -1)"
[ -n "$receipt" ]
grep -q '"transitions":\["queued","applied","archived"\]' "$receipt"
grep -q '^## 2026-01-02T00:00-change-demo$' "$work/.ai/changes/agent-skill-log.md"

# Explicit rejection is terminal and also archives rather than deleting.
printf 'not applied\n' > "$work/.ai/proposals/no-thanks.patch"
out="$(bash "$repo/templates/common/scripts/{{PREFIX}}-improve-drain.sh" "$work" \
  --reject no-thanks --reason 'fixture human gate declined')"
printf '%s' "$out" | grep -q '"outcome":"rejected"'
receipt="$(find "$work/.ai/proposals/archive/rejected" -name 'no-thanks.lifecycle.json' -print | head -1)"
[ -n "$receipt" ]
grep -q '"transitions":\["queued","rejected","archived"\]' "$receipt"

# A generator failure is not an applied proposal. Keep the queue intact and
# preserve the patched branch/worktree for diagnosis.
failed_work="$(mktemp -d "${TMPDIR:-/tmp}/cmp-proposal-build-fail.XXXXXX")"
git -C "$failed_work" init -q -b main
git -C "$failed_work" config core.autocrlf false
mkdir -p "$failed_work/templates" "$failed_work/.ai/proposals" \
  "$failed_work/.ai/changes" "$failed_work/lib"
printf 'before\n' > "$failed_work/templates/demo.txt"
printf '# fixture log\n' > "$failed_work/.ai/changes/agent-skill-log.md"
copy_lf "$fixture/change-demo.patch" "$failed_work/.ai/proposals/change-demo.patch"
copy_lf "$fixture/change-demo.changelog" "$failed_work/.ai/proposals/change-demo.changelog"
printf '%s\n' '#!/usr/bin/env bash' 'exit 9' > "$failed_work/lib/build-marketplace.sh"
chmod +x "$failed_work/lib/build-marketplace.sh"
git -C "$failed_work" add .
git -C "$failed_work" -c user.name=cmp-test -c user.email=cmp@example.invalid commit -qm fixture
failed_out="$(bash "$repo/templates/common/scripts/{{PREFIX}}-improve-drain.sh" "$failed_work")"
printf '%s' "$failed_out" | grep -q '"ok":false'
printf '%s' "$failed_out" | grep -q 'marketplace regeneration failed'
[ -f "$failed_work/.ai/proposals/change-demo.patch" ]
[ ! -d "$failed_work/.ai/proposals/archive/applied" ]
grep -q '^after$' "$failed_work/templates/demo.txt"

printf 'test-proposals: ok (%s)\n' "$work"
