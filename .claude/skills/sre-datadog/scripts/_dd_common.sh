#!/usr/bin/env bash
# Shared helpers for read-only Datadog API scripts. Source this file; do not execute.
# Sources:
#   https://docs.datadoghq.com/api/latest/authentication/
#   https://docs.datadoghq.com/api/latest/rate-limits/
#   https://docs.datadoghq.com/getting_started/site/ (site list, incl. us2.ddog-gov.com; matches OpenAPI servers enum)
# Keys are read from env (DD_API_KEY, DD_APP_KEY) and passed to curl via a
# header file on a private fd, so they never appear in argv, xtrace, or output.

set -euo pipefail

DD_SITE="${DD_SITE:-datadoghq.com}"
DD_BASE="https://api.${DD_SITE}"
DD_MAX_RETRIES="${DD_MAX_RETRIES:-3}"

dd_die() { printf 'error: %s\n' "$*" >&2; exit 1; }

dd_require_env() {
  [[ -n "${DD_API_KEY:-}" ]] || dd_die "DD_API_KEY is not set"
  [[ -n "${DD_APP_KEY:-}" ]] || dd_die "DD_APP_KEY is not set (use a scoped, read-only application key)"
  command -v curl >/dev/null || dd_die "curl not found"
  case "$DD_SITE" in
    datadoghq.com|us3.datadoghq.com|us5.datadoghq.com|datadoghq.eu|ap1.datadoghq.com|ap2.datadoghq.com|ddog-gov.com|us2.ddog-gov.com|uk1.datadoghq.com) ;;
    *) dd_die "unknown DD_SITE '$DD_SITE' (see https://docs.datadoghq.com/getting_started/site/)" ;;
  esac
}

# Validate a positive integer within [1, max].
dd_bound_int() {
  local name=$1 val=$2 max=$3
  if [[ ! "$val" =~ ^[0-9]+$ ]] || (( val < 1 || val > max )); then dd_die "$name must be an integer 1..$max (got '$val')"; fi
}

# dd_request METHOD PATH [curl args...]
# Only GET, or POST to an allow-listed read-only search endpoint.
dd_request() {
  local method=$1 path=$2; shift 2
  case "$method $path" in
    "GET /api/"*) ;;
    "POST /api/v2/logs/events/search"|"POST /api/v2/spans/events/search") ;;
    *) dd_die "refusing non-read-only request: $method $path" ;;
  esac

  local attempt=0 hdrs body code remaining reset wait
  hdrs=$(mktemp); body=$(mktemp)
  trap 'rm -f "$hdrs" "$body"' RETURN
  while :; do
    attempt=$((attempt + 1))
    code=$(curl -sS -X "$method" "${DD_BASE}${path}" \
      -H @<(printf 'DD-API-KEY: %s\nDD-APPLICATION-KEY: %s\n' "$DD_API_KEY" "$DD_APP_KEY") \
      -H 'Accept: application/json' \
      -D "$hdrs" -o "$body" -w '%{http_code}' --max-time 60 "$@") || dd_die "curl failed"
    remaining=$(awk -F': *' 'tolower($1)=="x-ratelimit-remaining"{gsub("\r","",$2);print $2}' "$hdrs")
    reset=$(awk -F': *' 'tolower($1)=="x-ratelimit-reset"{gsub("\r","",$2);print $2}' "$hdrs")
    if [[ "$code" == 429 ]]; then
      (( attempt <= DD_MAX_RETRIES )) || dd_die "rate limited (429) after $DD_MAX_RETRIES retries"
      wait=${reset:-$((2 ** attempt))}
      [[ "$wait" =~ ^[0-9]+$ ]] || wait=$((2 ** attempt))
      (( wait > 60 )) && wait=60
      printf 'rate limited; retrying in %ss (attempt %s/%s)\n' "$wait" "$attempt" "$DD_MAX_RETRIES" >&2
      sleep "$wait"; continue
    fi
    if [[ -n "$remaining" && "$remaining" =~ ^[0-9]+$ ]] && (( remaining < 2 )); then
      printf 'warning: X-RateLimit-Remaining=%s (reset in %ss)\n' "$remaining" "${reset:-?}" >&2
    fi
    cat "$body"; echo
    [[ "$code" =~ ^2 ]] || dd_die "HTTP $code from $method $path"
    return 0
  done
}
