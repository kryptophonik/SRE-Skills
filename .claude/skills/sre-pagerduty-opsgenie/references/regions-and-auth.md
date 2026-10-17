# Regions and authentication

| Vendor | API | US host | EU host | Auth header |
|---|---|---|---|---|
| PagerDuty | REST v2 | `https://api.pagerduty.com` | `https://api.eu.pagerduty.com` | `Authorization: Token token=$PD_API_KEY` + `Accept: application/vnd.pagerduty+json;version=2` |
| PagerDuty | Events v2 | `https://events.pagerduty.com/v2/enqueue` | `https://events.eu.pagerduty.com/v2/enqueue` | None. `routing_key` goes in the JSON body |
| PagerDuty | Hosted MCP | `https://mcp.pagerduty.com/mcp` | `https://mcp.eu.pagerduty.com/mcp` | OAuth (static client) or `Authorization: Token token=...` |
| Opsgenie | REST v2 | `https://api.opsgenie.com` | `https://api.eu.opsgenie.com` | `Authorization: GenieKey $OG_API_KEY` |

## Env vars used by this pack

| Var | What | Notes |
|---|---|---|
| `PD_API_KEY` | PagerDuty REST API key | Prefer a **read-only** key. A user-level key acts as that user |
| `PD_REGION` | `us` (default) or `eu` | Used by `scripts/lib.sh` |
| `PD_ROUTING_KEY` | Events API v2 integration key | Separate from `PD_API_KEY`. Anyone holding it can page your team. Sandbox key for tests |
| `OG_API_KEY` | Opsgenie API integration key | Give the integration read access only, not create/update/delete |
| `OG_REGION` | `us` (default) or `eu` | |

## Key differences

- **REST key vs routing key:** a REST key reads and changes account objects (incidents, schedules). A routing key only sends events to one service or ruleset. Never paste one where the other is expected.
- **`From:` header:** PagerDuty REST writes need `From: <email of a valid PD user>` when the key is account-level.
- **Opsgenie access:** the API integration must have the right access (team integrations are limited to their team). Otherwise you get `403` / `40301`.

## Secret hygiene

- Read keys from env vars or a secret manager only. Never hard-code them, `echo` them, or use `curl -v`/`--trace`, all of which print the auth header.
- `scripts/lib.sh` passes the header to curl on stdin (`-H @-`), so the key never shows up in `ps` output.

## Sources

- https://developer.pagerduty.com/docs/authentication
- https://support.pagerduty.com/main/docs/service-regions
- https://developer.pagerduty.com/docs/send-alert-event
- https://support.pagerduty.com/main/docs/pagerduty-mcp-server
- https://docs.opsgenie.com/docs/authentication
- https://docs.opsgenie.com/docs/who-is-on-call-api (EU host note, 40301)

## Unverified

- The exact `From:` rule (required with account-level keys, optional with user keys) is from memory of the PagerDuty API docs; I didn't re-fetch it.
- The names of Opsgenie integration access levels may differ in the UI.
