# Datadog MCP server: read-only setup

Sources (checked 2026-10-16):
- Setup, toolsets, permissions, auth: https://docs.datadoghq.com/bits_ai/mcp_server/setup/
- Tools reference: https://docs.datadoghq.com/bits_ai/mcp_server/tools/
- Endpoint values: https://github.com/DataDog/documentation/blob/master/hugo/assets/scripts/config/regions.config.js (the setup page renders the endpoint from this config through `region-param`)

Endpoint: `https://mcp.<site>/v1/mcp`. These are the per-site values Datadog's docs render (`mcp_server_endpoint` in https://github.com/DataDog/documentation/blob/master/hugo/assets/scripts/config/regions.config.js, checked 2026-10-16):

| Site | MCP endpoint |
|---|---|
| US1 | `https://mcp.datadoghq.com/v1/mcp` |
| US3 | `https://mcp.us3.datadoghq.com/v1/mcp` |
| US5 | `https://mcp.us5.datadoghq.com/v1/mcp` |
| EU1 | `https://mcp.datadoghq.eu/v1/mcp` |
| AP1 | `https://mcp.ap1.datadoghq.com/v1/mcp` |
| AP2 | `https://mcp.ap2.datadoghq.com/v1/mcp` |
| UK1 | `https://mcp.uk1.datadoghq.com/v1/mcp` |
| US1-FED (`ddog-gov.com`), US2-FED (`us2.ddog-gov.com`) | not supported |

The older path `https://mcp.<site>/api/unstable/mcp-server/mcp` still appears in third-party docs (for example https://docs.aws.amazon.com/devopsagent/latest/userguide/connecting-telemetry-sources-connecting-datadog.html) and still answers (an unauthenticated probe on 2026-10-16 returned HTTP 401 on both paths). Prefer `/v1/mcp`, which is the path the official docs use.
For Claude Code, Datadog recommends the plugin (`/plugin install datadog@claude-plugins-official`). Manual setup:

```json
{ "mcpServers": { "datadog": { "type": "http",
  "url": "https://mcp.datadoghq.com/v1/mcp?toolsets=core" } } }
```

## Toolsets and omit_tools
- With no `toolsets`, you get `core` only (logs, metrics, traces, dashboards, monitors, incidents, hosts, services, events, notebooks).
- Add only what you need, for example `?toolsets=core,alerting`. `toolsets=all` enables every GA toolset and costs context; preview toolsets (such as `apm`) have to be requested by name.
- `?omit_tools=a,b` removes tools after toolsets are resolved, for example `omit_tools=create_datadog_notebook,edit_datadog_notebook`.

## Enforce read-only (don't rely on prompts)
1. Role: grant `mcp_read` plus resource read permissions only, and leave out `mcp_write`. **Datadog Standard Role has both by default**, so use a custom role.
2. Org setting: turn **MCP Write Access** off, which hides write tools (such as `create_datadog_monitor`) for everyone.
3. Use `omit_tools` for any remaining write tools.
4. Optional: IP allowlist for the MCP server.

## Auth (in order of preference)
1. OAuth 2.0 (client handles it; revoke under Personal Settings > Authorized Apps).
2. PAT or SAT as `Authorization: Bearer <token>`.
3. `DD_API_KEY` / `DD_APPLICATION_KEY` HTTP headers, from a service account with a scoped key. Use env substitution and never put literal keys in the config.
