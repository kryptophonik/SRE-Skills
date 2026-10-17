#!/usr/bin/env bash
# READ-ONLY. List PagerDuty incidents (fully paginated).
# Usage: pd_incidents.sh [--since ISO8601] [--until ISO8601] [--status triggered|acknowledged|resolved]... [--json]
# Default: open incidents (triggered + acknowledged). Env: PD_API_KEY, PD_REGION=us|eu
# Ref: https://developer.pagerduty.com/api-reference/ (List incidents)
. "$(dirname "$0")/lib.sh"
q=""; st=0; json=0
while [ $# -gt 0 ]; do case "$1" in
  --since) q="$q&since=$(urlenc "$2")"; shift 2;;
  --until) q="$q&until=$(urlenc "$2")"; shift 2;;
  --status) case "$2" in triggered|acknowledged|resolved) ;; *) die "bad status $2";; esac
            q="$q&statuses%5B%5D=$2"; st=1; shift 2;;
  --json) json=1; shift;;
  -h|--help) sed -n 2,5p "$0"; exit 0;;
  *) die "unknown arg $1";; esac; done
[ "$st" = 1 ] || q="$q&statuses%5B%5D=triggered&statuses%5B%5D=acknowledged"
data=$(pd_paginate /incidents incidents "${q#&}")
if [ "$json" = 1 ]; then echo "$data"; exit 0; fi
echo "$data" | jq -r '[.incident_number, .status, (.urgency // "-"), .service.summary, .created_at, .title, .html_url] | @tsv' \
  | (echo -e "NUM\tSTATUS\tURGENCY\tSERVICE\tCREATED\tTITLE\tURL"; cat)
echo "total: $(echo -n "$data" | grep -c . || true)" >&2
