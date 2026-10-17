#!/usr/bin/env bash
# Show which fields a data object really has before you write a query against it.
#
# Usage:  check-fields.sh logs
#         check-fields.sh dt.davis.problems 2h
#
# Runs `fetch <object>, from: now()-<window> | limit 1` through dql.sh (read-only),
# and prints the field names of the sample record. For metrics use the
# fieldsSnapshot form in references/metrics-and-fields.md instead.

set -euo pipefail

obj=${1:?usage: check-fields.sh <data object> [window, default 1h]}
win=${2:-1h}
[[ "$obj" =~ ^[A-Za-z0-9_.]+$ ]] || { echo "check-fields.sh: bad data object name" >&2; exit 2; }
[[ "$win" =~ ^[0-9]+[mhd]$ ]] || { echo "check-fields.sh: window must look like 30m, 2h or 1d" >&2; exit 2; }

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
out=$("$here/dql.sh" "fetch ${obj}, from: now()-${win} | limit 1")
if command -v jq >/dev/null 2>&1; then
  # dtctl and the REST API both return records; the exact JSON shape from dtctl -o json
  # is not documented here, so fall back to printing the raw output.
  jq -r '(.records // .result.records // .)[0] | keys[]?' <<<"$out" 2>/dev/null || printf '%s\n' "$out"
else
  printf '%s\n' "$out"
fi
