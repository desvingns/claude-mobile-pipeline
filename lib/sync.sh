#!/usr/bin/env bash
# lib/sync.sh — consume the append-only change journal and refresh one adapter.
#
# Contract:
#   lib/sync.sh <claude|codex> [--changes-dir <dir>] [--root <dir>]
#
# The cursor is file-order based: an entry is new only when it appears after the
# stored id.  The state is updated atomically and only after adapter generation
# succeeds.  Stdout is reserved for exactly one JSON summary line.
set -u

die() {
    printf 'sync: %s\n' "$1" >&2
    exit 1
}

json_string_or_null() {
    if [ -n "$1" ]; then
        printf '"%s"' "$1"
    else
        printf 'null'
    fi
}

adapter="${1:-}"
[ "$adapter" = "claude" ] || [ "$adapter" = "codex" ] \
    || die 'first argument must be claude or codex'
shift

root="."
changes_dir=""
while [ $# -gt 0 ]; do
    case "$1" in
        --root)
            [ $# -ge 2 ] || die '--root requires a directory'
            root="$2"
            shift 2
            ;;
        --changes-dir)
            [ $# -ge 2 ] || die '--changes-dir requires a directory'
            changes_dir="$2"
            shift 2
            ;;
        -h|--help)
            sed -n '2,8p' "$0"
            exit 0
            ;;
        *) die "unknown argument: $1" ;;
    esac
done

[ -d "$root" ] || die "root does not exist: $root"
root="$(cd "$root" && pwd)"
[ -n "$changes_dir" ] || changes_dir="$root/.ai/changes"
if [ -d "$changes_dir" ]; then
    changes_dir="$(cd "$changes_dir" && pwd)"
else
    die "changes directory does not exist: $changes_dir"
fi

log="$changes_dir/agent-skill-log.md"
state="$changes_dir/sync-state.json"
[ -f "$log" ] || die "change log not found: $log"
[ -f "$state" ] || die "sync state not found: $state"

# The state schema is deliberately tiny.  Reconstructing either legal key order
# validates the complete JSON without depending on jq/python in generated apps.
compact_state="$(tr -d '[:space:]' < "$state")"
claude_token="$(printf '%s' "$compact_state" | sed -n 's/.*"claude":\([^,}]*\).*/\1/p')"
codex_token="$(printf '%s' "$compact_state" | sed -n 's/.*"codex":\([^,}]*\).*/\1/p')"
[ -n "$claude_token" ] && [ -n "$codex_token" ] || die 'malformed sync-state.json'
case "$compact_state" in
    "{\"claude\":$claude_token,\"codex\":$codex_token}"|\
    "{\"codex\":$codex_token,\"claude\":$claude_token}") ;;
    *) die 'malformed sync-state.json' ;;
esac

decode_cursor() {
    case "$1" in
        null) printf '' ;;
        \"*\")
            value="${1#\"}"; value="${value%\"}"
            case "$value" in
                [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]-*) ;;
                *) return 1 ;;
            esac
            slug="${value:17}"
            case "$slug" in ''|*[!A-Za-z0-9._-]*) return 1 ;; esac
            printf '%s' "$value"
            ;;
        *) return 1 ;;
    esac
}

claude_cursor="$(decode_cursor "$claude_token")" || die 'malformed claude cursor'
codex_cursor="$(decode_cursor "$codex_token")" || die 'malformed codex cursor'
if [ "$adapter" = "claude" ]; then
    cursor="$claude_cursor"
else
    cursor="$codex_cursor"
fi

# Validate the whole journal before doing any work.  Existing history contains
# a few repeated target: lines and mp-improve authors; both are accepted as
# backward-compatible producer extensions, while the pinned required fields,
# ids, types, ordering and affects vocabulary stay strict.
if ! entries="$(awk '
function malformed(message) {
    print "sync: malformed change log: " message > "/dev/stderr"
    bad=1
}
function finish( normalized) {
    if (!open) return
    if (id == "" || type == "" || target_count == 0 || summary == "" || reason == "" || !affects_seen || by == "")
        malformed("entry " id " is missing a required field")
    if (type !~ /^(add|update|fix|remove)$/)
        malformed("entry " id " has invalid type")
    if (id !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]-[[:alnum:]_.-][[:alnum:]_.-]*$/)
        malformed("invalid id: " id)
    if (seen[id]++) malformed("duplicate id: " id)
    if (previous != "" && id <= previous) malformed("ids are not monotonic at " id)
    previous=id
    normalized=affects
    gsub(/[[:space:]]/, "", normalized)
    if (normalized != "" && normalized != "claude" && normalized != "codex" && normalized != "claude,codex" && normalized != "codex,claude")
        malformed("entry " id " has invalid affects")
    print id "\t" normalized
}
/^## / {
    finish()
    open=1
    id=substr($0,4)
    sub(/\r$/, "", id)
    type=summary=reason=affects=by=""
    target_count=affects_seen=0
    next
}
!open { next }
/^type:/    { type=substr($0,6); sub(/^[[:space:]]*/,"",type); sub(/\r$/, "", type); next }
/^target:/  { target_count++; next }
/^summary:/ { summary=substr($0,9); sub(/^[[:space:]]*/,"",summary); sub(/\r$/, "", summary); next }
/^reason:/  { reason=substr($0,8); sub(/^[[:space:]]*/,"",reason); sub(/\r$/, "", reason); next }
/^affects:/ { affects=substr($0,9); sub(/^[[:space:]]*/,"",affects); sub(/\r$/, "", affects); affects_seen=1; next }
/^by:/      { by=substr($0,4); sub(/^[[:space:]]*/,"",by); sub(/\r$/, "", by); next }
/^[[:space:]]*$/ { next }
{ malformed("unexpected content in entry " id) }
END { finish(); if (bad) exit 2 }
' "$log")"; then
    exit 1
fi

processed=0
to="$cursor"
cursor_found=false
[ -z "$cursor" ] && cursor_found=true

while IFS="$(printf '\t')" read -r id affects; do
    [ -n "$id" ] || continue
    if [ "$cursor_found" = false ]; then
        if [ "$id" = "$cursor" ]; then
            cursor_found=true
        fi
        continue
    fi
    [ "$id" = "$cursor" ] && continue
    case ",$affects," in
        *,"$adapter",*)
            processed=$((processed + 1))
            to="$id"
            ;;
    esac
done <<EOF
$entries
EOF

[ "$cursor_found" = true ] || die "cursor id is not present in change log: $cursor"

generate_agents_md() {
    local agents_dir="$root/.claude/agents"
    local commands_dir="$root/.claude/commands"
    local ownership_stamp="$root/.claude/.cmp-version"
    local project prefix version command_file overview out tmp file title description contract
    local marker archive_kind archive_dir archive_dest archive_stamp
    [ -d "$agents_dir" ] || die "cannot generate codex adapter: missing $agents_dir"
    [ -f "$ownership_stamp" ] \
        || die "cannot generate codex adapter: missing cmp ownership stamp $ownership_stamp"

    project="$(basename "$root")"
    if [ -f "$root/.claude/mp/config.json" ]; then
        description="$(sed -n 's/.*"projectName"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$root/.claude/mp/config.json" | head -1)"
        [ -z "$description" ] || project="$description"
    fi
    prefix="$(sed -n 's/^prefix:[[:space:]]*//p' "$ownership_stamp" | head -1)"
    version="$(sed -n 's/^version:[[:space:]]*//p' "$ownership_stamp" | head -1)"
    case "$prefix" in ''|*[!A-Za-z0-9._-]*) die "invalid prefix in $ownership_stamp" ;; esac
    case "$version" in ''|*[!A-Za-z0-9._-]*) die "invalid version in $ownership_stamp" ;; esac
    command_file=""
    if [ -d "$commands_dir" ]; then
        for file in "$commands_dir"/*.md; do
            [ -f "$file" ] || continue
            command_file="$file"
            [ "$prefix" = pipeline ] && prefix="$(basename "$file" .md)"
            break
        done
    fi
    overview="Run the canonical $prefix pipeline; its command and agent specifications live under .claude/."
    if [ -n "$command_file" ]; then
        description="$(sed -n 's/^description:[[:space:]]*//p' "$command_file" | head -1)"
        [ -z "$description" ] || overview="$description"
    fi

    out="$root/AGENTS.md"
    tmp="${out}.tmp.$$"
    marker="<!-- cmp-generated-adapter: codex version=$version prefix=$prefix -->"
    {
        printf '# AGENTS.md — %s pipeline\n\n' "$project"
        printf '%s\n\n' "$marker"
        printf 'Generated by cmp v%s. Canonical workflow: run the `%s` pipeline.\n\n' "$version" "$prefix"
        printf '## Pipeline\n\n%s\n\n' "$overview"
        printf '## Agents\n\n'
        for file in "$agents_dir"/*.md; do
            [ -f "$file" ] || continue
            title="$(sed -n 's/^#[[:space:]]*//p' "$file" | head -1)"
            [ -n "$title" ] || title="$(basename "$file" .md)"
            description="$(sed -n 's/^description:[[:space:]]*//p' "$file" | head -1)"
            if [ -z "$description" ]; then
                description="Canonical role specification: \`.claude/agents/$(basename "$file")\`."
            fi
            contract=JSON
            grep -qi 'BRAINSTORM block' "$file" && contract=BRAINSTORM
            printf '### %s\n\n%s\n\nOutput contract: %s.\n\n' "$title" "$description" "$contract"
        done
        printf '## Memory & handoff\n\n'
        printf 'Use the shared `.ai/memory/` index for durable project knowledge and `.ai/handoff.md` for current work.\n'
    } > "$tmp" || die "cannot write $tmp"

    # Preserve every previous adapter. A missing marker means the file may be
    # user-authored, so place it in an explicit protected bucket and warn on
    # stderr while keeping stdout's one-JSON-line contract intact.
    if [ -e "$out" ] || [ -L "$out" ]; then
        archive_kind="protected-user-file"
        if grep -Eq '^<!-- cmp-generated-adapter: codex version=[A-Za-z0-9._-]+ prefix=[A-Za-z0-9._-]+ -->\r?$' "$out"; then
            archive_kind="previous-generated"
        else
            printf 'sync: preserving non-generated AGENTS.md before adapter refresh\n' >&2
        fi
        archive_stamp="$(date -u +%Y%m%dT%H%M%SZ)-$$"
        archive_dir="$root/.ai/archive/adapters/$archive_stamp/$archive_kind"
        archive_dest="$archive_dir/AGENTS.md"
        mkdir -p "$archive_dir" || die "cannot create adapter archive: $archive_dir"
        [ ! -e "$archive_dest" ] && [ ! -L "$archive_dest" ] \
            || archive_dest="${archive_dest}.$$"
        mv "$out" "$archive_dest" || die "cannot archive existing AGENTS.md"
    fi
    mv "$tmp" "$out" || die "cannot replace $out"
}

regenerate_adapter() {
    if [ -x "$root/lib/build-marketplace.sh" ] && [ -d "$root/templates" ]; then
        # The repository generator currently rebuilds both committed plugin trees in
        # one deterministic pass.  Cursor isolation still remains per adapter.
        (cd "$root" && bash lib/build-marketplace.sh >/dev/null) \
            || die "adapter generation failed for $adapter"
    elif [ "$adapter" = "codex" ]; then
        generate_agents_md
    elif [ -d "$root/.claude" ]; then
        # The Claude tree is canonical in a generated project, so no derived file
        # is needed; consuming its cursor is the complete adapter operation.
        :
    else
        die "no adapter generator found under $root"
    fi
}

if [ "$processed" -gt 0 ]; then
    regenerate_adapter
    if [ "$adapter" = "claude" ]; then
        claude_token="\"$to\""
    else
        codex_token="\"$to\""
    fi
    state_tmp="${state}.tmp.$$"
    printf '{ "claude": %s, "codex": %s }\n' "$claude_token" "$codex_token" > "$state_tmp" \
        || die "cannot write temporary state: $state_tmp"
    mv "$state_tmp" "$state" || die "cannot replace sync state: $state"
fi

printf '{"adapter":"%s","processed":%d,"from":%s,"to":%s}\n' \
    "$adapter" "$processed" "$(json_string_or_null "$cursor")" "$(json_string_or_null "$to")"
