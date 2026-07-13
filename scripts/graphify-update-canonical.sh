#!/usr/bin/env bash
# Rebuild Graphify from canonical sources while preserving the previous graph.
set -eu

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
repo_root="$(cd "$repo_root" && pwd -P)"
graph_dir="$repo_root/graphify-out"
archive_root="$repo_root/archive/graphify"

case "$graph_dir" in
  "$repo_root"/*) ;;
  *)
    printf '%s\n' '{"ok":false,"error":"graph path escaped repository"}'
    exit 2
    ;;
esac

if ! command -v graphify >/dev/null 2>&1; then
  printf '%s\n' '{"ok":false,"error":"graphify command not found"}'
  exit 127
fi

stamp="$(date -u +%Y%m%dT%H%M%SZ)-$$"
archive_dir="$archive_root/$stamp"
log_file="$archive_dir/update.log"
archived_graph=""
mkdir -p "$archive_dir"

if [ -d "$graph_dir" ]; then
  archived_graph="$archive_dir/graphify-out"
  mv "$graph_dir" "$archived_graph"
fi

if graphify update "$repo_root" --force >"$log_file" 2>&1; then
  if [ -n "$archived_graph" ]; then
    printf '{"ok":true,"rebuilt":true,"previous_graph":"%s","log":"%s"}\n' \
      "$archived_graph" "$log_file"
  else
    printf '{"ok":true,"rebuilt":true,"previous_graph":null,"log":"%s"}\n' \
      "$log_file"
  fi
  exit 0
else
  status=$?
fi

failed_graph=""
restored_previous=false

# Graphify can create a partial graphify-out before returning non-zero. Preserve
# that failed evidence separately, then always restore the last known-good graph.
if [ -e "$graph_dir" ] || [ -L "$graph_dir" ]; then
  failed_graph="$archive_dir/failed/graphify-out"
  if ! mkdir -p "$(dirname "$failed_graph")" || ! mv "$graph_dir" "$failed_graph"; then
    printf '{"ok":false,"error":"graphify update failed and partial output could not be archived","status":%s,"log":"%s"}\n' \
      "$status" "$log_file"
    exit "$status"
  fi
fi
if [ -n "$archived_graph" ] && [ -d "$archived_graph" ]; then
  if ! mv "$archived_graph" "$graph_dir"; then
    printf '{"ok":false,"error":"graphify update failed and previous graph could not be restored","status":%s,"failed_graph":"%s","log":"%s"}\n' \
      "$status" "$failed_graph" "$log_file"
    exit "$status"
  fi
  restored_previous=true
fi
if [ -n "$failed_graph" ]; then
  printf '{"ok":false,"error":"graphify update failed","status":%s,"failed_graph":"%s","restored_previous":%s,"log":"%s"}\n' \
    "$status" "$failed_graph" "$restored_previous" "$log_file"
else
  printf '{"ok":false,"error":"graphify update failed","status":%s,"failed_graph":null,"restored_previous":%s,"log":"%s"}\n' \
    "$status" "$restored_previous" "$log_file"
fi
exit "$status"
