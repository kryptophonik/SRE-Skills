# MCP servers for this skill pack

Skills work without MCP by giving commands for you to run. With these servers connected, Claude Code can run the read-only steps itself. Every server below was checked via web search on 2026-10-16; deprecated ones are marked. Dynatrace guidance was reviewed against Dynatrace dynatrace-for-ai skills. **Start every server read-only.** Writes still go through [sre-safety-gates](../.claude/skills/sre-safety-gates/SKILL.md).

Add a server with `claude mcp add` or a project `.mcp.json`. Keep tokens in environment variables or your secret manager, never in the repo.

| Tool | Server | Repo / docs | Read-only setting |
|---|---|---|---|
| Dynatrace | **Recommended:** Dynatrace for AI skills + `dtctl` locally, or the Dynatrace Remote MCP Server. Local `@dynatrace-oss/dynatrace-mcp-server` is **DEPRECATED** (final release 2.1.2). | https://github.com/Dynatrace/dynatrace-for-ai · https://docs.dynatrace.com/docs/dynatrace-intelligence/dynatrace-mcp · deprecated: https://github.com/dynatrace-oss/dynatrace-mcp | Grant only the read scopes listed below. `send_slack_message`, `send_email`, `send_event`, `create_dynatrace_notebook` need approval; writing documents needs `document:documents:write`, which stays omitted in read-only config. |
| Kubernetes | kubernetes-mcp-server | https://github.com/containers/kubernetes-mcp-server | `--read-only` (or `read_only = true` in TOML). Bind a read-only ServiceAccount (`view` ClusterRole). |
| Grafana / Prometheus / Loki | mcp-grafana | https://github.com/grafana/mcp-grafana | `--disable-write`; service account with Viewer role. Add `--enable-query` only if datasource credentials are read-only. |
| Datadog | Datadog managed MCP server | https://github.com/datadog-labs/mcp-server (endpoint `https://mcp.datadoghq.com/v1/mcp`, or your site, e.g. `.eu`) | Authenticate as a user/role with read-only permissions. |
| PagerDuty | PagerDuty remote MCP (`https://mcp.pagerduty.com/mcp`) | https://support.pagerduty.com/main/docs/pagerduty-mcp-server · archived local: https://github.com/PagerDuty/pagerduty-mcp-server | Local server is read-only unless started with `--enable-write-tools` (do not add it). Remote: use a read-only user/OAuth scope. |
| Opsgenie | No official MCP server found | — | Use the REST API with a read-only API key (`pagerduty-opsgenie` skill). Opsgenie support ends 2027-04-05. |
| Terraform | HashiCorp Terraform MCP server | https://github.com/hashicorp/terraform-mcp-server | Registry lookups are read-only. Leave HCP Terraform token unset, or use a read-only team token; run/workspace actions are writes. (awslabs and Azure Terraform MCP servers are deprecated.) |
| AWS | AWS API MCP server (awslabs) | https://github.com/awslabs/mcp (`src/aws-api-mcp-server`) | `READ_OPERATIONS_ONLY=true`; optionally `REQUIRE_MUTATION_CONSENT=true`. IAM `ReadOnlyAccess`-style role is the real control. |
| Azure | Azure MCP Server | https://github.com/microsoft/mcp (`servers/Azure.Mcp.Server`) | `azmcp server start --read-only`; Reader role on the subscription. |
| Google Cloud | gcloud MCP and observability MCP (local); Google remote MCP servers | https://github.com/googleapis/gcloud-mcp · https://github.com/google/mcp · https://docs.cloud.google.com/mcp | Use an account/service account with Viewer roles (`roles/viewer`, `roles/logging.viewer`, `roles/monitoring.viewer`). |
| GitHub | GitHub MCP server | https://github.com/github/github-mcp-server | Use `--read-only` and a fine-grained read-only token; link deploys/PRs to incidents. |

## Dynatrace setup details

Environment variables (local server):

- `DT_ENVIRONMENT` (required): `https://<env-id>.apps.dynatrace.com`
- Auth, one of: `DT_PLATFORM_TOKEN`, or `OAUTH_CLIENT_ID` + `OAUTH_CLIENT_SECRET`
- `DT_GRAIL_QUERY_BUDGET_GB` (default `1000`): cap Grail scan volume; set lower
- `DT_SSO_URL`: custom SSO endpoint, if used
- `DT_MCP_TOKEN_STORAGE=file`: persist tokens to file
- `DT_MCP_DISABLE_TELEMETRY`: opt out of telemetry
- `MCP_BEARER_TOKEN`: protects the server in HTTP mode

Read-only scopes to grant:

- `app-engine:apps:run`
- `storage:buckets:read`, `storage:logs:read`, `storage:metrics:read`, `storage:events:read`, `storage:entities:read`, `storage:spans:read`, `storage:smartscape:read`, `storage:system:read`
- Optional: `document:documents:read`

Scopes to omit in read-only config: `storage:events:write`, `email:emails:send`, `document:documents:write`, `app-settings:objects:read`.

## Example `.mcp.json` (read-only)

Genuine config example. Replace placeholders; keep secrets in env vars.

```json
{
  "mcpServers": {
    "kubernetes": { "command": "npx", "args": ["-y", "kubernetes-mcp-server@latest", "--read-only"] },
    "grafana": {
      "command": "uvx", "args": ["mcp-grafana", "--disable-write"],
      "env": { "GRAFANA_URL": "https://grafana.example.com", "GRAFANA_SERVICE_ACCOUNT_TOKEN": "${GRAFANA_SA_TOKEN}" }
    },
    "dynatrace": {
      "command": "npx", "args": ["-y", "@dynatrace-oss/dynatrace-mcp-server@latest"],
      "env": { "DT_ENVIRONMENT": "https://<env-id>.apps.dynatrace.com", "DT_PLATFORM_TOKEN": "${DT_PLATFORM_TOKEN}", "DT_GRAIL_QUERY_BUDGET_GB": "50" }
    },
    "datadog": { "type": "http", "url": "https://mcp.datadoghq.com/v1/mcp" },
    "pagerduty": { "type": "http", "url": "https://mcp.pagerduty.com/mcp" },
    "aws-api": {
      "command": "uvx", "args": ["awslabs.aws-api-mcp-server@latest"],
      "env": { "AWS_REGION": "us-east-1", "READ_OPERATIONS_ONLY": "true", "REQUIRE_MUTATION_CONSENT": "true" }
    },
    "azure": { "command": "npx", "args": ["-y", "@azure/mcp@latest", "server", "start", "--read-only"] },
    "terraform": { "command": "docker", "args": ["run", "-i", "--rm", "hashicorp/terraform-mcp-server"] }
  }
}
```

The `dynatrace` entry uses the deprecated local server; prefer Dynatrace for AI + `dtctl` or the Remote MCP Server. Check each server's README for current auth options (OAuth vs. tokens) and env var names before use; they change often.

## Extra guardrails

- Deny write tools in Claude Code permissions as a second layer (e.g. `"deny": ["mcp__kubernetes__resources_delete"]`); names come from `/mcp`.
- Separate prod and non-prod servers/credentials; name them clearly (`kubernetes-prod`).
- Audit: most vendors log API calls; tag the MCP identity so its actions are traceable.
