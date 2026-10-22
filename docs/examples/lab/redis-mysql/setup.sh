#!/usr/bin/env bash
# setup.sh LAB_DIR: start the Redis and MySQL labs for docs/examples/03.
#   redis-lab on 127.0.0.1:56379: maxmemory 4mb, noeviction, an admin password and the read-only
#             user sre-ro with the ACL from references/redis.md (redis-acl.txt).
#   mysql-lab on 127.0.0.1:53306: users app, sre_ro (references/mysql.md) and operator, table shop.orders.
# Writes into LAB_DIR (create it with mktemp -d), all mode 600: generated passwords (*.pw), redis.conf,
# MySQL option files (app.cnf, sre_ro.cnf, operator.cnf; root-local.cnf is for docker exec) and env.sh (no secrets in it).
# Passwords are never echoed or put on a command line. Needs: docker, python3. Undo: teardown.sh LAB_DIR.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
lab="${1:?usage: setup.sh LAB_DIR (create it with mktemp -d)}"
[ -d "$lab" ] || { echo "no such directory: $lab" >&2; exit 2; }
lab="$(cd "$lab" && pwd)"
for c in redis-lab mysql-lab; do
  if docker container inspect "$c" >/dev/null 2>&1; then
    echo "container $c already exists: run teardown.sh first" >&2; exit 1
  fi
done
umask 077
touch "$lab/.redis-mysql-lab"   # marker: teardown.sh only deletes directories it set up
for u in redis-admin redis-sre-ro mysql-root app sre_ro operator; do
  python3 -c 'import secrets; print(secrets.token_urlsafe(24))' > "$lab/$u.pw"
done

# Redis: everything in a config file, read by the container as your uid (no secrets in argv).
{
  printf 'requirepass %s\n' "$(cat "$lab/redis-admin.pw")"
  printf 'user sre-ro on >%s %s\n' "$(cat "$lab/redis-sre-ro.pw")" "$(cat "$here/redis-acl.txt")"
  printf '%s\n' 'maxmemory 4mb' 'maxmemory-policy noeviction' 'slowlog-log-slower-than 5000' \
    'save ""' 'appendonly no' 'dir /tmp'
} > "$lab/redis.conf"
docker run -d --name redis-lab --user "$(id -u):$(id -g)" -p 127.0.0.1:56379:6379 \
  -v "$lab/redis.conf:/usr/local/etc/redis/redis.conf:ro" \
  redis:7.4 redis-server /usr/local/etc/redis/redis.conf >/dev/null

# MySQL option files (one per account).
cnf() { # file user pwfile [extra line]
  {
    printf '[client]\nhost=127.0.0.1\nport=53306\nuser=%s\npassword=%s\n' "$2" "$(cat "$lab/$3.pw")"
    if [ $# -ge 4 ]; then printf '%s\n' "$4"; fi
  } > "$lab/$1"
}
cnf app.cnf app app
cnf sre_ro.cnf sre_ro sre_ro ssl
cnf operator.cnf operator operator
{ printf '[client]\nuser=root\npassword=%s\n' "$(cat "$lab/mysql-root.pw")"; } > "$lab/root-local.cnf"

docker run -d --name mysql-lab --user "$(id -u):$(id -g)" -p 127.0.0.1:53306:3306 \
  -e MYSQL_ROOT_PASSWORD_FILE=/run/secrets/root.pw -v "$lab/mysql-root.pw:/run/secrets/root.pw:ro" \
  -v "$lab/root-local.cnf:/run/secrets/root.cnf:ro" mysql:8.4 >/dev/null
myroot() { docker exec -i mysql-lab mysql --defaults-extra-file=/run/secrets/root.cnf "$@"; }
ready=0
for _ in $(seq 120); do
  # TCP check: the image's temporary init server does not listen on TCP
  if myroot -h 127.0.0.1 -N -e 'SELECT 1' >/dev/null 2>&1; then ready=1; break; fi
  sleep 1
done
[ "$ready" = 1 ] || { echo "mysql-lab did not become ready" >&2; exit 1; }
{
  printf "CREATE USER 'app'@'%%' IDENTIFIED BY '%s';\n" "$(cat "$lab/app.pw")"
  printf "CREATE USER 'sre_ro'@'%%' IDENTIFIED BY '%s' REQUIRE SSL WITH MAX_USER_CONNECTIONS 3;\n" "$(cat "$lab/sre_ro.pw")"
  printf "CREATE USER 'operator'@'%%' IDENTIFIED BY '%s';\n" "$(cat "$lab/operator.pw")"
  cat "$here/mysql.sql"
} | myroot

cat > "$lab/env.sh" <<ENV
# Redis read-only user for db-ro.sh (the password is read from the file, never typed)
export REDIS_HOST=127.0.0.1 REDIS_PORT=56379 REDIS_USER=sre-ro
REDISCLI_AUTH="\$(cat '$lab/redis-sre-ro.pw')"; export REDISCLI_AUTH
# MySQL read-only account for db-ro.sh
export MYSQL_DEFAULTS_FILE='$lab/sre_ro.cnf'
# Admin redis-cli for the lab and the approved actions (password from the file, not argv)
radmin() { REDISCLI_AUTH="\$(cat '$lab/redis-admin.pw')" redis-cli -h 127.0.0.1 -p 56379 --no-auth-warning "\$@"; }
ENV
echo "redis-lab ready on 127.0.0.1:56379, mysql-lab ready on 127.0.0.1:53306 (lab files in $lab)"
