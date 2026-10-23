#!/usr/bin/env bash
# Read-only version check for "PHP2Shell" (CVE-2026-109618, CVE-2026-109619), two critical
# unauthenticated RCE flaws fixed upstream in PHP 8.2.35 / 8.3.36 / 8.4.27 / 8.5.12
# (2026-10-21). Never patches, restarts or execs into anything; it only reads a version.
#
# Three independent, read-only modes (use any combination):
#   --local            run `php -v` and a best-effort package-manager query on THIS host
#   --url <url>        one HEAD request per URL; best-effort X-Powered-By/Server header only
#                       (most production configs strip this; absence proves nothing)
#   --text <file>       parse `php -v`, `php -i`/phpinfo(), or a package-manager query you
#                       already captured elsewhere (e.g. via an approved kubectl exec) --
#                       this script never execs into a container or remote host itself
#
# Prints one line per source:  STATUS  SOURCE  VERSION  DETAIL
# STATUS: VULNERABLE (confirmed below the fixed build for its branch, or an EOL branch with
#         no modern vendor fix), CHECK-DISTRO-PACKAGE (Debian/Ubuntu-style backports keep the
#         same upstream version string after patching -- `php -v` alone cannot clear this host),
#         PATCHED, UNKNOWN (no version found) or ERROR (usage/connection).
# Exit 0 only if every source is PATCHED. Exit 1 if any is VULNERABLE, CHECK-DISTRO-PACKAGE or
# UNKNOWN (none of those are a clean result). Exit 2 on a usage or connection error. The exit
# code is the worst single result across all sources -- read the per-line STATUS when checking
# more than one.
set -uo pipefail
urls=""; texts=""; do_local=0; timeout=10
usage() { echo "usage: $0 [--local] [--timeout SEC] [--url http(s)://host[:port][/path] ...] [--text dump.txt ...]" >&2; exit 2; }
while [ $# -gt 0 ]; do
  case "$1" in
    --local) do_local=1; shift ;;
    --timeout) [ $# -ge 2 ] || usage; case "$2" in ''|*[!0-9]*) usage ;; esac; timeout=$2; shift 2 ;;
    --url) [ $# -ge 2 ] || usage; urls="$urls $2"; shift 2 ;;
    --text) [ $# -ge 2 ] || usage; texts="$texts $2"; shift 2 ;;
    -h|--help) usage ;;
    *) usage ;;
  esac
done
[ "$do_local" = 1 ] || [ -n "$urls$texts" ] || usage
command -v python3 >/dev/null || { echo "python3 not found" >&2; exit 2; }

CLASSIFY_PY=''
IFS= read -r -d '' CLASSIFY_PY <<'PY' || true
import sys, re
source, kind, text = sys.argv[1], sys.argv[2], sys.stdin.read()
# Fixed (upstream) builds per branch, released 2026-10-21 for CVE-2026-109618 / CVE-2026-109619.
FIXED = {(8, 5): (8, 5, 12), (8, 4): (8, 4, 27), (8, 3): (8, 3, 36), (8, 2): (8, 2, 35)}
# Branches that only ever got a source-only backport (EOL, no official binary release):
# verify against your vendor's own advisory, don't assume this host is covered.
BACKPORT_ONLY = {(7, 4), (8, 0), (8, 1)}

m = re.search(r'PHP[\s/](\d+)\.(\d+)\.(\d+)', text)
if not m:
    print(f"UNKNOWN {source} - no-php-version-found-in-{kind}")
    sys.exit(1)
ver = tuple(int(x) for x in m.groups())
branch = ver[:2]

if branch in FIXED:
    status = "PATCHED" if ver >= FIXED[branch] else "VULNERABLE"
    detail = f"fixed-at-{'.'.join(map(str, FIXED[branch]))}"
elif branch in BACKPORT_ONLY:
    status, detail = "CHECK-DISTRO-PACKAGE", "eol-branch-source-backport-only-verify-vendor-advisory"
elif branch > (8, 5):
    status, detail = "PATCHED", "newer-than-the-affected-branches"
else:
    status, detail = "VULNERABLE", "eol-branch-no-modern-vendor-fix-upgrade-the-branch"

print(f"{status} {source} {'.'.join(map(str, ver))} {detail}")
sys.exit(0 if status == "PATCHED" else 1)
PY

rc=0
classify() { # $1=source $2=kind, stdin=text to scan for "PHP X.Y.Z"
  python3 -c "$CLASSIFY_PY" "$1" "$2"
  r=$?; [ $r -gt $rc ] && rc=$r
}

if [ "$do_local" = 1 ]; then
  if command -v php >/dev/null; then
    php -v 2>/dev/null | classify "local" "php -v"
  else
    echo "UNKNOWN local - php-not-on-PATH"; [ 1 -gt $rc ] && rc=1
  fi
  # Package-manager version, best-effort: on Debian/Ubuntu-style distros a security backport
  # keeps the same upstream version string, so `php -v` alone cannot confirm this host is
  # patched. Surface the package version/changelog date so the operator can compare it against
  # the vendor's own advisory date (the fix shipped 2026-10-21), not against the PHP version.
  if command -v dpkg >/dev/null 2>&1; then
    pkg=$(dpkg -l 'php*' 2>/dev/null | awk '/^ii/{print $2, $3}')
    if [ -n "$pkg" ]; then
      echo "CHECK-DISTRO-PACKAGE local dpkg: $pkg -- compare its changelog date to 2026-10-21, not its version number"
      [ 1 -gt $rc ] && rc=1
    fi
  elif command -v rpm >/dev/null 2>&1; then
    pkg=$(rpm -qa 'php*' --queryformat '%{NAME}-%{VERSION}-%{RELEASE}\n' 2>/dev/null)
    if [ -n "$pkg" ]; then
      echo "CHECK-DISTRO-PACKAGE local rpm: $pkg -- compare its build date to 2026-10-21, not its version number"
      [ 1 -gt $rc ] && rc=1
    fi
  elif command -v apk >/dev/null 2>&1; then
    pkg=$(apk info -a php 2>/dev/null | head -n1)
    if [ -n "$pkg" ]; then
      echo "CHECK-DISTRO-PACKAGE local apk: $pkg -- compare against your distro's own advisory, not the version number"
      [ 1 -gt $rc ] && rc=1
    fi
  fi
fi

for f in $texts; do
  [ -r "$f" ] || { echo "ERROR $f - not-readable"; [ 2 -gt $rc ] && rc=2; continue; }
  classify "$f" "captured-text" < "$f"
done

for u in $urls; do
  command -v curl >/dev/null || { echo "curl not found" >&2; exit 2; }
  hdr=$(curl -s -m "$timeout" -I "$u" 2>/dev/null) || hdr=""
  if [ -z "$hdr" ]; then
    echo "ERROR $u - connect-failed"; [ 2 -gt $rc ] && rc=2; continue
  fi
  powered=$(printf '%s' "$hdr" | grep -i '^X-Powered-By:' | head -n1)
  if [ -z "$powered" ]; then
    echo "UNKNOWN $u - X-Powered-By-not-sent-prod-configs-usually-hide-this-absence-proves-nothing"
    [ 1 -gt $rc ] && rc=1
  else
    # Not a pipeline: classify must run in this shell so its exit code reaches rc.
    classify "$u" "X-Powered-By header" <<<"$powered"
  fi
done
exit $rc
