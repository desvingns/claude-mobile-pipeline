#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/cmp-graphify-wrapper.XXXXXX")"
bin="$work/bin"
mkdir -p "$bin" "$work/graphify-out"
git -C "$work" init -q
printf 'known-good\n' > "$work/graphify-out/previous.txt"

cat > "$bin/graphify" <<'EOF'
#!/usr/bin/env bash
root="${2:?missing graph root}"
mkdir -p "$root/graphify-out"
printf 'partial\n' > "$root/graphify-out/partial.txt"
exit 7
EOF
chmod +x "$bin/graphify"

set +e
out="$(cd "$work" && PATH="$bin:$PATH" bash "$repo/scripts/graphify-update-canonical.sh")"
status=$?
set -e
[ "$status" -eq 7 ]
printf '%s' "$out" | grep -q '"ok":false'
printf '%s' "$out" | grep -q '"restored_previous":true'
[ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" -eq 1 ]
grep -q '^known-good$' "$work/graphify-out/previous.txt"
[ ! -e "$work/graphify-out/partial.txt" ]
failed="$(find "$work/archive/graphify" -path '*/failed/graphify-out/partial.txt' -type f -print -quit)"
[ -n "$failed" ]
grep -q '^partial$' "$failed"

printf 'test-graphify-wrapper: ok (%s)\n' "$work"
