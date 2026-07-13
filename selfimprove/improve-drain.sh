#!/usr/bin/env bash
# Root-kit entrypoint for the canonical proposal lifecycle implementation.
set -u
root="$(cd "$(dirname "$0")/.." && pwd)"
exec bash "$root/templates/common/scripts/{{PREFIX}}-improve-drain.sh" "$root" "$@"
