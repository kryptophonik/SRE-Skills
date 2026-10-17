#!/usr/bin/env bash
# Read-only list of monitors currently in Alert: GET /api/v1/monitor/search
# Source: https://docs.datadoghq.com/api/latest/monitors/#monitors-search
# Scope: monitors_read (OpenAPI AuthZ: https://github.com/DataDog/datadog-api-client-python/blob/master/.generator/schemas/v1/openapi.yaml)
# Usage: dd_monitors_alerting.sh ['extra filter, e.g. tag:"service:web"'] [per_page (1..100, default 30)]
set -euo pipefail
# shellcheck source=_dd_common.sh
source "$(dirname "${BASH_SOURCE[0]}")/_dd_common.sh"
dd_require_env
extra=${1:-}
per_page=${2:-30}
dd_bound_int per_page "$per_page" 100
q="status:alert${extra:+ ${extra}}"
dd_request GET /api/v1/monitor/search -G \
  --data-urlencode "query=${q}" --data-urlencode "per_page=${per_page}" --data-urlencode "page=0"
