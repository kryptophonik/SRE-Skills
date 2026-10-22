#!/usr/bin/env bash
# setup.sh LAB_DIR: start the Postgres lab for docs/examples/02 (container pg-lab on 127.0.0.1:15432).
# Writes into LAB_DIR (create it with mktemp -d): generated passwords (*.pw), pgpass (mode 600)
# and env.sh (connection settings, no secrets). Passwords are never echoed or put on a command line.
# Needs: docker, python3, psql on the host. Undo with teardown.sh LAB_DIR.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
lab="${1:?usage: setup.sh LAB_DIR (create it with mktemp -d)}"
[ -d "$lab" ] || { echo "no such directory: $lab" >&2; exit 2; }
lab="$(cd "$lab" && pwd)"
name=pg-lab port=15432

if docker container inspect "$name" >/dev/null 2>&1; then
  echo "container $name already exists: run teardown.sh first" >&2; exit 1
fi
umask 077
touch "$lab/.pg-lab"   # marker: teardown.sh only deletes directories it set up
for u in postgres sre_ro ops shop; do
  python3 -c 'import secrets; print(secrets.token_urlsafe(24))' > "$lab/$u.pw"
done
: > "$lab/pgpass"
for u in sre_ro ops shop; do
  printf '127.0.0.1:%s:*:%s:%s\n' "$port" "$u" "$(cat "$lab/$u.pw")" >> "$lab/pgpass"
done
cat > "$lab/env.sh" <<ENV
export PGPASSFILE='$lab/pgpass' PGHOST=127.0.0.1 PGPORT=$port PGDATABASE=shop PGUSER=sre_ro
unset PGPASSWORD PGOPTIONS PGSERVICE
ENV

# Runs as your uid so it can read the mode-600 password file; PGDATA is a subdirectory it can create.
docker run -d --name "$name" --user "$(id -u):$(id -g)" -p "127.0.0.1:$port:5432" \
  -e PGDATA=/var/lib/postgresql/data/pg -e POSTGRES_PASSWORD_FILE=/run/secrets/pw \
  -v "$lab/postgres.pw:/run/secrets/pw:ro" \
  postgres:17 -c max_connections=20 -c log_lock_waits=on >/dev/null

wait_ready() {
  for _ in $(seq 60); do
    if docker exec "$name" pg_isready -q -h 127.0.0.1 -U postgres 2>/dev/null; then return 0; fi
    sleep 1
  done
  echo "$name did not become ready" >&2; exit 1
}
psql_su() { docker exec -i "$name" psql -X -q -v ON_ERROR_STOP=1 -U postgres "$@"; }
wait_ready   # TCP check: the image's temporary init server listens on the socket only

# reserved_connections is a server-start setting: set it, then restart (as in production).
psql_su -c "ALTER SYSTEM SET reserved_connections = 3"
docker restart "$name" >/dev/null
wait_ready

psql_su -d postgres < "$here/roles.sql"
for u in sre_ro ops shop; do
  printf "ALTER ROLE %s PASSWORD '%s';\n" "$u" "$(python3 "$here/scram.py" "$lab/$u.pw")"
done | psql_su -d postgres
docker exec -i "$name" psql -X -q -v ON_ERROR_STOP=1 -U shop -d shop < "$here/seed.sql"

echo "pg-lab ready on 127.0.0.1:$port (lab files in $lab)"
