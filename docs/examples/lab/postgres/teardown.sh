#!/usr/bin/env bash
# teardown.sh LAB_DIR: stop the sessions from hold.sh, remove container pg-lab and delete LAB_DIR
# (only if setup.sh created its files there).
set -euo pipefail
lab="${1:?usage: teardown.sh LAB_DIR}"
if [ -f "$lab/pids" ]; then
  while read -r pg; do kill -- "-$pg" 2>/dev/null || true; done < "$lab/pids"
fi
docker rm -f -v pg-lab >/dev/null 2>&1 || true
if [ -f "$lab/.pg-lab" ]; then rm -rf "$lab"; fi
echo "pg-lab removed"
