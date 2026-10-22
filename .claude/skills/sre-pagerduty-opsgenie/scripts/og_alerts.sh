#!/usr/bin/env bash
# READ-ONLY. List Opsgenie alerts (fully paginated).
# Usage: og_alerts.sh [--query 'status:open'] [--json]
# Env: OG_API_KEY, OG_REGION=us|eu
# Ref: https://docs.opsgenie.com/docs/alert-api (List alerts) · https://docs.opsgenie.com/docs/pagination
. "$(dirname "$0")/lib.sh"
query="status:open"; json=0
while [ $# -gt 0 ]; do case "$1" in
  --query) query=$2; shift 2;; --json) json=1; shift;;
  -h|--help) sed -n 2,4p "$0"; exit 0;; *) die "unknown arg $1";; esac; done
data=$(og_paginate "/v2/alerts?query=$(urlenc "$query")&limit=100&sort=createdAt&order=desc") || exit 2
if [ "$json" = 1 ]; then echo "$data"; exit 0; fi
echo "$data" | jq -r '[.tinyId, .status, (.acknowledged|tostring), .priority, .createdAt, .message] | @tsv' \
  | (echo -e "TINY_ID\tSTATUS\tACKED\tPRIORITY\tCREATED\tMESSAGE"; cat)
echo "total: $(echo -n "$data" | grep -c . || true)" >&2
