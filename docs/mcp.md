# MCP servers for this skill pack

Skills work without MCP by giving commands for you to run. With these servers connected, Claude Code can run the read-only steps itself. Every server below was checked to exist on 2026-10-16. **Start every server read-only.** Writes still go through [sre-safety-gates](../.claude/skills/sre-safety-gates/SKILL.md).

Add a server with `claude mcp add` or a project `.mcp.json`. Keep tokens in environment variables or your secret manager, never in the repo.

| Tool | Server | Repo / docs | Read-only setting |
|---|---|---|---|
| Dynatrace | Dynatrace MCP (local `@dynatrace-oss/dynatrace-mcp-server`, or Dynatrace Remote MCP) | https://github.com/dynatrace-oss/dynatrace-mcp · https://docs.dynatrace.com/docs/dynatrace-intelligence/dynatrace-mcp | Use a platform token / OAuth client with only `storage:*:read` and needed read scopes. Do not grant notification/automation scopes unless needed; `send_slack_message`, `send_email`, `send_event` need approval. |
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
      "env": { "DT_ENVIRONMENT": "https://<env-id>.apps.dynatrace.com" }
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

Check each server's README for current auth options (OAuth vs. tokens) and env var names before use; they change often.

## Extra guardrails

- Deny write tools in Claude Code permissions as a second layer (e.g. `"deny": ["mcp__kubernetes__resources_delete"]`); names come from `/mcp`.
- Separate prod and non-prod servers/credentials; name them clearly (`kubernetes-prod`).
- Audit: most vendors log API calls; tag the MCP identity so its actions are traceable.
