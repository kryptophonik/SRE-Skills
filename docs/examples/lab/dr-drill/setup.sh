#!/usr/bin/env bash
# setup.sh LAB_DIR: start the source database for docs/examples/08 (DR restore drill).
# Container pg-dr-src (postgres:17) with --network none: no ports, reachable only with docker exec,
# so trust auth inside it is safe and there are no passwords. Loads the shop data from
# ../postgres/seed.sql, then stands in for app history: every order was last written 20 minutes
# ago, and order 42 was later marked shipped by code that doesn't touch updated_at.
# Writes LAB_DIR/backups/ (empty) and a marker. Needs: docker. Undo: teardown.sh LAB_DIR.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
lab="${1:?usage: setup.sh LAB_DIR (create it with mktemp -d)}"
[ -d "$lab" ] || { echo "no such directory: $lab" >&2; exit 2; }
lab="$(cd "$lab" && pwd)"
if docker container inspect pg-dr-src >/dev/null 2>&1; then
  echo "container pg-dr-src already exists: run teardown.sh first" >&2; exit 1
fi
umask 077
touch "$lab/.dr-drill-lab"; mkdir -p "$lab/backups"
docker run -d --name pg-dr-src --network none --label purpose=dr-source \
  -e POSTGRES_HOST_AUTH_METHOD=trust postgres:17 >/dev/null
ready=0
for _ in $(seq 60); do
  # wait for the real server: the image's temporary init server stops once after initdb
  if docker logs pg-dr-src 2>&1 | grep -q 'PostgreSQL init process complete' \
     && docker exec pg-dr-src pg_isready -q -U postgres 2>/dev/null; then ready=1; break; fi
  sleep 1
done
[ "$ready" = 1 ] || { echo "pg-dr-src did not become ready" >&2; exit 1; }
psql_src() { docker exec -i pg-dr-src psql -X -q -v ON_ERROR_STOP=1 -U postgres "$@"; }
psql_src -c 'CREATE ROLE shop LOGIN' -c 'CREATE DATABASE shop OWNER shop'
docker exec -i pg-dr-src psql -X -q -v ON_ERROR_STOP=1 -U shop -d shop < "$here/../postgres/seed.sql"
psql_src -d shop -c "UPDATE orders SET updated_at = now() - interval '20 minutes'" \
  -c "UPDATE orders SET status = 'shipped' WHERE id = 42"
echo "pg-dr-src ready (no network; lab files in $lab)"
