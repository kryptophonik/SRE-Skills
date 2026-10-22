#!/usr/bin/env bash
# teardown.sh LAB_DIR: remove pg-dr-src and, if still there, the drill container pg-dr-drtest
# (same name and label guard as the page), then delete LAB_DIR if setup.sh created it.
set -euo pipefail
lab="${1:?usage: teardown.sh LAB_DIR}"
n=pg-dr-drtest
if [ "$(docker inspect -f '{{index .Config.Labels "purpose"}}' "$n" 2>/dev/null || true)" = dr-drill ]; then
  docker rm -f "$n" >/dev/null
fi
docker rm -f pg-dr-src >/dev/null 2>&1 || true
if [ -f "$lab/.dr-drill-lab" ]; then rm -rf "$lab"; fi
echo "pg-dr-src removed"
