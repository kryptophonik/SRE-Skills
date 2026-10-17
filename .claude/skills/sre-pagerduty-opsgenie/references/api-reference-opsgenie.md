# Opsgenie API v2 reference (read-only first)

> Opsgenie end of support is **April 5, 2027** (https://www.atlassian.com/licensing/opsgenie). See [opsgenie-migration.md](opsgenie-migration.md).

```bash
OG_HOST="https://api.opsgenie.com"   # EU: https://api.eu.opsgenie.com
OG=(-sS -H "Authorization: GenieKey $OG_API_KEY")
```

## Opsgenie v2 (read-only)

List endpoints take `offset` and `limit` (alerts: max 100). Follow `paging.next` in the response until it's missing. Sources: https://docs.opsgenie.com/docs/pagination · https://docs.opsgenie.com/docs/alert-api

```bash
og_get() {  # og_get <path-with-query> [jq-projection]; follows paging.next, capped at MAX_PAGES (default 10)
  local url="$OG_HOST$1" proj=${2:-.} pages=0
  while [ -n "$url" ] && [ "$url" != "null" ] && [ "$pages" -lt "${MAX_PAGES:-10}" ]; do
    r=$(curl "${OG[@]}" "$url"); echo "$r" | jq -c ".data[]? | $proj"
    url=$(echo "$r" | jq -r '.paging.next // empty'); pages=$((pages+1))
  done
}
og_get "/v2/alerts?query=status%3Aopen&limit=100"        # open alerts
curl "${OG[@]}" "$OG_HOST/v2/alerts/<ALERT_ID>"            # one alert
curl "${OG[@]}" "$OG_HOST/v2/schedules"                     # schedules
curl "${OG[@]}" "$OG_HOST/v2/schedules/<SCHEDULE_ID>/timeline?expand=base,forwarding,override"
curl "${OG[@]}" "$OG_HOST/v2/schedules/<SCHEDULE_ID>/overrides"
curl "${OG[@]}" "$OG_HOST/v2/schedules/<SCHEDULE_NAME>/on-calls?scheduleIdentifierType=name&flat=true"
curl "${OG[@]}" "$OG_HOST/v2/schedules/<SCHEDULE_ID>/next-on-calls"
curl "${OG[@]}" "$OG_HOST/v2/escalations"
curl "${OG[@]}" "$OG_HOST/v2/teams"
og_get "/v2/users?limit=100"
curl "${OG[@]}" "$OG_HOST/v2/users/<USER_ID>/contacts"
curl "${OG[@]}" "$OG_HOST/v2/users/<USER_ID>/notification-rules"
```

Sources: https://docs.opsgenie.com/docs/schedule-api · https://docs.opsgenie.com/docs/schedule-override-api · https://docs.opsgenie.com/docs/who-is-on-call-api · https://docs.opsgenie.com/docs/escalation-api · https://docs.opsgenie.com/docs/team-api · https://docs.opsgenie.com/docs/user-api · https://docs.opsgenie.com/docs/contact-api · https://docs.opsgenie.com/docs/notification-rule-api

### Opsgenie writes (WRITE, approval required)

Alert actions are asynchronous. They return **202** with a `requestId`. Confirm the action took effect with the request-status call (`data.isSuccess`).

```bash
r=$(curl "${OG[@]}" -X POST -H "Content-Type: application/json" \
  "$OG_HOST/v2/alerts/<ALERT_ID>/acknowledge" -d '{"user":"<you>","source":"claude-sre","note":"<text>"}')
# close: same shape, path /v2/alerts/<ALERT_ID>/close
req=$(echo "$r" | jq -r .requestId)
curl "${OG[@]}" "$OG_HOST/v2/alerts/requests/$req"   # check data.isSuccess / data.status
```

Source: https://docs.opsgenie.com/docs/alert-api

## Unverified

- Opsgenie pagination: `offset`/`limit`/`paging.next` behaviour is from the doc structure, not a full read. Some list endpoints (teams, schedules, escalations) may not paginate at all.
- The heartbeats list returns `data.heartbeats` (an object), not an array. The scripts store it as returned.
- jq paths not tested against a live account.
