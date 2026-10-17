#!/usr/bin/env bash
# Read-only metric timeseries query: GET /api/v1/query
# Source: https://docs.datadoghq.com/api/latest/metrics/#query-timeseries-points
# Scope: timeseries_query (OpenAPI AuthZ: https://github.com/DataDog/datadog-api-client-python/blob/master/.generator/schemas/v1/openapi.yaml)
# Usage: dd_query.sh '<metric query>' [minutes_back (1..1440, default 60)]
set -euo pipefail
# shellcheck source=_dd_common.sh
source "$(dirname "${BASH_SOURCE[0]}")/_dd_common.sh"
dd_require_env
query=${1:?usage: dd_query.sh "<query>" [minutes_back]}
mins=${2:-60}
dd_bound_int minutes_back "$mins" 1440
to=$(date +%s); from=$((to - mins * 60))
dd_request GET /api/v1/query -G \
  --data-urlencode "from=${from}" --data-urlencode "to=${to}" --data-urlencode "query=${query}"
