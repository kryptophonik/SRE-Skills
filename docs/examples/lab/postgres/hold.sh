#!/usr/bin/env bash
# hold.sh LAB_DIR COUNT APP SQL: open COUNT background psql sessions as user shop with
# application_name APP; each runs SQL (%d becomes 1..COUNT) and then sits idle for 15 minutes.
# Session process groups are recorded in LAB_DIR/pids so teardown.sh can stop them.
set -euo pipefail
lab="${1:?usage: hold.sh LAB_DIR COUNT APP SQL}"; count="${2:?count}"; app="${3:?app}"; sql="${4:?sql}"
[ -f "$lab/.pg-lab" ] || { echo "not a pg-lab directory: $lab" >&2; exit 2; }
# shellcheck disable=SC1091
. "$lab/env.sh"
set -m   # each background job gets its own process group
i=1
while [ "$i" -le "$count" ]; do
  # shellcheck disable=SC2059
  stmt="$(printf "$sql" "$i")"
  ( printf '%s\n' "$stmt"; sleep 900 ) | PGAPPNAME="$app" PGUSER=shop psql -X -q >/dev/null 2>&1 &
  i=$((i + 1))
done
jobs -p >> "$lab/pids"
sleep 2
