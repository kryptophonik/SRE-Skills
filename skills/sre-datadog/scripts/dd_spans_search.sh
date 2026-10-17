#!/usr/bin/env bash
# Read-only span search: POST /api/v2/spans/events/search (search, not a write)
# Source: https://docs.datadoghq.com/api/latest/spans/#search-spans
# Scope: apm_read (OpenAPI AuthZ)
# Body schema SpansListRequest: data.type=search_request; attributes.filter{query,from,to};
#   sort in {timestamp,-timestamp}; page.limit default 10, max 1000
#   (https://github.com/DataDog/datadog-api-client-python/blob/master/.generator/schemas/v2/openapi.yaml)
# Usage: dd_spans_search.sh '<span query>' [minutes_back (1..1440, default 15)] [limit (1..1000, default 50)]
set -euo pipefail
# shellcheck source=_dd_common.sh
source "$(dirname "${BASH_SOURCE[0]}")/_dd_common.sh"
dd_require_env
command -v jq >/dev/null || dd_die "jq required"
query=${1:?usage: dd_spans_search.sh "<query>" [minutes_back] [limit]}
mins=${2:-15}; limit=${3:-50}
dd_bound_int minutes_back "$mins" 1440
dd_bound_int limit "$limit" 1000
payload=$(jq -n --arg q "$query" --arg from "now-${mins}m" --argjson l "$limit" \
  '{data:{type:"search_request",attributes:{filter:{query:$q,from:$from,to:"now"},sort:"-timestamp",page:{limit:$l}}}}')
dd_request POST /api/v2/spans/events/search -H 'Content-Type: application/json' --data "$payload"
