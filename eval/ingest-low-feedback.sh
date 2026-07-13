#!/usr/bin/env bash
# Convert feedback scores <=3 into idempotent human-triage eval candidates.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
python_bin="${PYTHON:-}"
if [ -z "$python_bin" ]; then
  if command -v python3 >/dev/null 2>&1; then python_bin=python3
  elif command -v python >/dev/null 2>&1; then python_bin=python
  else printf '%s\n' '{"ok":false,"error":"python 3 is required"}'; exit 2
  fi
fi
exec "$python_bin" "$here/runner.py" ingest-low-feedback "$@"
