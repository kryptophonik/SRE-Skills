#!/usr/bin/env bash
# teardown.sh LAB_DIR: remove containers redis-lab and mysql-lab and delete LAB_DIR
# (only if setup.sh created its files there).
set -euo pipefail
lab="${1:?usage: teardown.sh LAB_DIR}"
docker rm -f redis-lab mysql-lab >/dev/null 2>&1 || true
if [ -f "$lab/.redis-mysql-lab" ]; then rm -rf "$lab"; fi
echo "redis-lab and mysql-lab removed"
