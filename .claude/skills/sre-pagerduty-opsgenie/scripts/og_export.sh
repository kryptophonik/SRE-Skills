#!/usr/bin/env bash
# READ-ONLY. Export Opsgenie config for migration planning (GET only).
# Writes JSON files into --out DIR (created, mode 700). Output contains PII and
# integration details: store encrypted, never commit, delete after migration.
# Usage: og_export.sh --out DIR
# Env: OG_API_KEY, OG_REGION=us|eu
# Ref: team-api, schedule-api, schedule-override-api, escalation-api, heartbeat-api,
#      integration-api, user-api, contact-api, notification-rule-api at https://docs.opsgenie.com/docs/
. "$(dirname "$0")/lib.sh"
out=""
while [ $# -gt 0 ]; do case "$1" in --out) out=$2; shift 2;; -h|--help) sed -n 2,7p "$0"; exit 0;; *) die "unknown arg $1";; esac; done
[ -n "$out" ] || die "--out DIR required"
umask 077; mkdir -p "$out"
base=$(og_base)
for p in teams schedules escalations heartbeats integrations; do
  og_paginate "/v2/$p" > "$out/$p.jsonl"; echo "$p: $(grep -c . "$out/$p.jsonl" || true)" >&2
done
og_paginate "/v2/users?limit=100" > "$out/users.jsonl"; echo "users: $(grep -c . "$out/users.jsonl" || true)" >&2
mkdir -p "$out/schedules" "$out/users" "$out/integrations"
while read -r id; do [ -n "$id" ] || continue
  api_get GET og "$base/v2/schedules/$id" > "$out/schedules/$id.json"
  api_get GET og "$base/v2/schedules/$id/overrides" > "$out/schedules/$id.overrides.json"
done < <(jq -r .id "$out/schedules.jsonl")
while read -r id; do [ -n "$id" ] || continue
  api_get GET og "$base/v2/users/$id/contacts" > "$out/users/$id.contacts.json"
  api_get GET og "$base/v2/users/$id/notification-rules" > "$out/users/$id.notification-rules.json"
done < <(jq -r .id "$out/users.jsonl")
while read -r id; do [ -n "$id" ] || continue
  api_get GET og "$base/v2/integrations/$id" > "$out/integrations/$id.json"
done < <(jq -r .id "$out/integrations.jsonl")
echo "export written to $out (contains PII; handle accordingly)" >&2
