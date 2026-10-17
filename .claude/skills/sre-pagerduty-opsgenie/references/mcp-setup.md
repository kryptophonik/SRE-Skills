# PagerDuty MCP setup (Claude Code)

## Status

- **Current:** PagerDuty-hosted MCP server, `https://mcp.pagerduty.com/mcp` (EU: `https://mcp.eu.pagerduty.com/mcp`). Nothing to install. Supports OAuth or an API key.
- **Deprecated:** the local server (`pagerduty-mcp`, `uvx pagerduty-mcp`, env `PAGERDUTY_USER_API_KEY`). Its repo, https://github.com/PagerDuty/pagerduty-mcp-server, is archived. It is read-only unless started with `--enable-write-tools`.
- **Opsgenie:** I found no official MCP server. Use the REST API (`api-reference-opsgenie.md`).

## The hosted server is NOT read-only

It exposes write tools, and PagerDuty says tool filtering isn't available on the hosted server. To limit which tools succeed, use a **scoped OAuth client**.

| Read tools | Write tools (approval required) |
|---|---|
| `browse_incidents`, `browse_services`, `browse_schedules`, `browse_teams`, `browse_event_orchestrations`, `browse_alert_grouping`, `browse_status_pages`, `browse_escalation_policies`, `browse_users`, `browse_change_events`, `browse_activity` | `manage_incidents` (create, update, add_note, add_responders, start_workflow), `manage_services`, `manage_schedules` (incl. create_override), `manage_teams` (incl. delete), `manage_event_orchestrations`, `manage_alert_grouping` (incl. delete), `manage_status_pages` (create_post, create_post_update) |

## Connect

PagerDuty does **not** support Dynamic Client Registration. OAuth in Claude Code therefore needs a pre-created OAuth client (`clientId`) and a fixed callback port that matches the redirect URI registered on that client.

```bash
# OAuth (scoped, read-only client recommended). Redirect URI on the client: http://localhost:8080/callback
MCP_CLIENT_SECRET=<client-secret> claude mcp add-json pagerduty \
  '{"type":"http","url":"https://mcp.pagerduty.com/mcp","oauth":{"clientId":"<client-id>","callbackPort":8080}}' --client-secret

# API key (use a read-only key)
PAGERDUTY_API_KEY=<read-only-key> claude mcp add-json pagerduty \
  '{"type":"http","url":"https://mcp.pagerduty.com/mcp","headers":{"Authorization":"Token token=${PAGERDUTY_API_KEY}"}}'
```

EU accounts: replace the URL with `https://mcp.eu.pagerduty.com/mcp`.

## Deny write tools in Claude Code (second layer)

Add this to `.claude/settings.json`. The tool names follow Claude Code's `mcp__<server>__<tool>` pattern; confirm the exact names with `/mcp`.

```json
{
  "permissions": {
    "deny": [
      "mcp__pagerduty__manage_incidents",
      "mcp__pagerduty__manage_services",
      "mcp__pagerduty__manage_schedules",
      "mcp__pagerduty__manage_teams",
      "mcp__pagerduty__manage_event_orchestrations",
      "mcp__pagerduty__manage_alert_grouping",
      "mcp__pagerduty__manage_status_pages"
    ]
  }
}
```

If you need writes, move the specific tool to `ask` rather than `allow`, and still follow [sre-safety-gates](../../sre-safety-gates/SKILL.md).

## Sources

- https://support.pagerduty.com/main/docs/pagerduty-mcp-server (hosted URL, EU URL, auth, no DCR, Claude Code commands, tool table, no tool filtering)
- https://github.com/PagerDuty/pagerduty-mcp-server (archived local server, `--enable-write-tools`)

## Unverified

- The OAuth scope names a read-only client needs (PagerDuty uses scopes like `escalation_policies.read` per endpoint; I didn't check the full list).
- The exact MCP tool names Claude Code shows for the hosted server. Check with `/mcp` before relying on the deny list.
- The hosted tool list changes over time; recheck the support page.
