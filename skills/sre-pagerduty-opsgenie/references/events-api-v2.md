# PagerDuty Events API v2 (PAGES PEOPLE, approval required)


- `routing_key` is the 32-character **Integration Key** of an Events API v2 integration on a service or ruleset. It is **not** the REST API key and it doesn't use the `Authorization` header.
- Always set `dedup_key`. Without it, every trigger opens a new alert. Ack and resolve only apply when they use the same `routing_key` as the trigger.
- Test only against a sandbox service whose escalation policy targets a test user. Never use a production routing key for tests.

```bash
# PAGES PEOPLE: trigger
curl -sS -X POST "$PD_EVENTS/v2/enqueue" -H "Content-Type: application/json" -d "{
  \"routing_key\": \"$PD_ROUTING_KEY\",
  \"event_action\": \"trigger\",
  \"dedup_key\": \"<stable-key-e.g.-service/check>\",
  \"payload\": {\"summary\": \"<summary>\", \"source\": \"<host-or-fqdn>\", \"severity\": \"critical|error|warning|info\"}
}"
# acknowledge / resolve: same routing_key + dedup_key
curl -sS -X POST "$PD_EVENTS/v2/enqueue" -H "Content-Type: application/json" \
  -d "{\"routing_key\":\"$PD_ROUTING_KEY\",\"dedup_key\":\"<same-key>\",\"event_action\":\"resolve\"}"
```

Source: https://developer.pagerduty.com/docs/send-alert-event


## Hosts

- US: `https://events.pagerduty.com/v2/enqueue` · EU: `https://events.eu.pagerduty.com/v2/enqueue`

## Rules

- Running any of these calls is a page. It needs explicit approval under [sre-safety-gates](../../sre-safety-gates/SKILL.md), even for a test.
- `PD_ROUTING_KEY` is an integration key, not `PD_API_KEY`. Keep them in separate env vars. Never put a routing key in a repo, because anyone holding it can page your team.
- Tests go only to a sandbox service whose escalation policy targets a test user.

## Sources

- https://developer.pagerduty.com/docs/send-alert-event
- https://support.pagerduty.com/main/docs/service-regions

## Unverified

- Events API response codes and rate limits (on the Events API v2 overview page, which I didn't fetch).
