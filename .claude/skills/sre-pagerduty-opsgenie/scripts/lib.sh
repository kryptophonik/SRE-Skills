#!/usr/bin/env bash
# Shared READ-ONLY helpers for PagerDuty / Opsgenie scripts. Source, don't execute.
# - Only GET is allowed (api_get refuses anything else).
# - Keys only from env: PD_API_KEY, OG_API_KEY. Sent to curl over stdin (-H @-), never in argv, never echoed.
# - Region: PD_REGION=us|eu, OG_REGION=us|eu (default us).
# - MAX_PAGES (default 20) caps pages per paginated call; HTTP 429 is retried with backoff (up to 3 times).
# - PD_BASE_URL / OG_BASE_URL override the host (for tests); only https:// or http://127.0.0.1|localhost accepted.
set -euo pipefail

die() { echo "ERROR: $*" >&2; exit 2; }
need() { command -v "$1" >/dev/null 2>&1 || die "missing dependency: $1"; }
need curl; need jq

_check_base() {
  case "$1" in
    https://*|http://127.0.0.1:*|http://localhost:*) ;;
    *) die "refusing base URL '$1' (must be https:// or local test host)";;
  esac
}

pd_base() {
  local b
  if [ -n "${PD_BASE_URL:-}" ]; then b=$PD_BASE_URL
  else case "${PD_REGION:-us}" in us) b=https://api.pagerduty.com;; eu) b=https://api.eu.pagerduty.com;; *) die "PD_REGION must be us or eu";; esac
  fi
  _check_base "$b"; printf '%s' "$b"
}
og_base() {
  local b
  if [ -n "${OG_BASE_URL:-}" ]; then b=$OG_BASE_URL
  else case "${OG_REGION:-us}" in us) b=https://api.opsgenie.com;; eu) b=https://api.eu.opsgenie.com;; *) die "OG_REGION must be us or eu";; esac
  fi
  _check_base "$b"; printf '%s' "$b"
}

# api_get METHOD VENDOR URL  -> prints body. VENDOR = pd|og.
api_get() {
  local method=$1 vendor=$2 url=$3 hdr
  [ "$method" = "GET" ] || die "read-only helper: refusing $method (only GET allowed). Writes go through sre-safety-gates."
  case "$vendor" in
    pd) [ -n "${PD_API_KEY:-}" ] || die "PD_API_KEY not set"
        hdr=$(printf 'Authorization: Token token=%s\nAccept: application/vnd.pagerduty+json;version=2' "$PD_API_KEY");;
    og) [ -n "${OG_API_KEY:-}" ] || die "OG_API_KEY not set"
        hdr=$(printf 'Authorization: GenieKey %s' "$OG_API_KEY");;
    *) die "unknown vendor $vendor";;
  esac
  local out code try=0
  while :; do
    out=$(printf '%s\n' "$hdr" | curl -sS -X GET -H @- --max-time 60 -w '\n%{http_code}' "$url") || die "request failed: ${url%%\?*}"
    code=${out##*$'\n'}; out=${out%$'\n'*}
    [ "$code" = "429" ] && [ "$try" -lt 3 ] || break
    try=$((try+1)); echo "WARN: HTTP 429, retry $try/3" >&2; sleep $((try*${RETRY_BASE_SECONDS:-2}))
  done
  case "$code" in 2??) printf '%s' "$out";; *) echo "$out" | jq -c . >&2 2>/dev/null || true; die "HTTP $code from ${url%%\?*}";; esac
}

# pd_paginate PATH COLLECTION_KEY [QUERY]  -> JSON lines, follows limit/offset/more.
# Ref: https://developer.pagerduty.com/docs/pagination
pd_paginate() {
  local path=$1 key=$2 q=${3:-} off=0 base r pages=0 max=${MAX_PAGES:-20}
  base=$(pd_base)
  while :; do
    [ "$pages" -lt "$max" ] || { echo "WARN: stopped at MAX_PAGES=$max; narrow the window or raise MAX_PAGES" >&2; break; }
    pages=$((pages+1))
    r=$(api_get GET pd "$base$path?limit=100&offset=$off${q:+&$q}")
    jq -c --arg k "$key" '.[$k][]?' <<<"$r"
    [ "$(jq -r '.more // false' <<<"$r")" = "true" ] || break
    off=$((off+100))
    [ "$off" -lt 10000 ] || die "offset limit reached (classic pagination caps at 10000); narrow the query"
  done
}

# og_paginate PATH_WITH_QUERY -> JSON lines from .data[], follows paging.next on the same host only.
# Ref: https://docs.opsgenie.com/docs/pagination
og_paginate() {
  local base url r next pages=0 max=${MAX_PAGES:-20}
  base=$(og_base); url="$base$1"
  while [ -n "$url" ]; do
    [ "$pages" -lt "$max" ] || { echo "WARN: stopped at MAX_PAGES=$max; narrow the query or raise MAX_PAGES" >&2; break; }
    pages=$((pages+1))
    r=$(api_get GET og "$url")
    jq -c 'if (.data|type)=="array" then .data[] else .data end' <<<"$r"
    next=$(jq -r '.paging.next // empty' <<<"$r")
    if [ -n "$next" ]; then
      case "$next" in "$base"/*) url=$next;; *) die "paging.next points to another host; refusing";; esac
    else url=""; fi
  done
}

urlenc() { jq -rn --arg v "$1" '$v|@uri'; }
