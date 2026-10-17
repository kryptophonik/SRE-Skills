# MCP servers for this skill pack

Skills work without MCP by giving commands for you to run. With these servers connected, Claude Code can run the read-only steps itself. Every server below was checked via web search on 2026-10-16; deprecated ones are marked. Dynatrace guidance was reviewed against Dynatrace dynatrace-for-ai skills. **Start every server read-only.** Writes still go through [sre-safety-gates](../.claude/skills/sre-safety-gates/SKILL.md).

Add a server with `claude mcp add` or a project `.mcp.json`. Keep tokens in environment variables or your secret manager, never in the repo.

| Tool | Server | Repo / docs | Read-only setting |
|---|---|---|---|
| Dynatrace | **Recommended:** Dynatrace for AI skills + `dtctl` locally, or the Dynatrace Remote MCP Server. Local `@dynatrace-oss/dynatrace-mcp-server` is **DEPRECATED** (final release 2.1.2). | https://github.com/Dynatrace/dynatrace-for-ai · https://docs.dynatrace.com/docs/dynatrace-intelligence/dynatrace-mcp · deprecated: https://github.com/dynatrace-oss/dynatrace-mcp | Grant only the read scopes listed below. `send_slack_message`, `send_email`, `send_event`, `create_dynatrace_notebook` need approval; writing documents needs `document:documents:write`, which stays omitted in read-only config. |
| Kubernetes | kubernetes-mcp-server | https://github.com/containers/kubernetes-mcp-server | Current releases dropped runtime CLI flags such as `--read-only`: set `read_only = true` in a TOML file passed with `--config`, deny Secrets with `[[denied_resources]]`, and **pin the version**. Bind a `view`-based Role/ClusterRole (no `secrets`, `pods/exec`, `pods/portforward`, `pods/attach`). Add Claude Code deny rules for write tools (below). |
| Grafana / Prometheus / Loki | mcp-grafana | https://github.com/grafana/mcp-grafana | `--disable-write`; service account with Viewer role. Add `--enable-query` only if datasource credentials are read-only. |
| Datadog | Datadog MCP server (remote) — endpoint `https://mcp.<site>/api/unstable/mcp-server/mcp`; also Claude Code plugin `datadog@claude-plugins-official`. GovCloud unsupported. | https://docs.datadoghq.com/bits_ai/mcp_server/setup/ | **Writes are on by default** (Standard role has `mcp_write`). Enforce read-only: custom role with only `mcp_read`, org-level MCP Write Access off, or `?omit_tools=` for write tools (e.g. `create_datadog_monitor`, `create/edit_datadog_notebook`; names unverified). Default toolset `core`; narrow with `?toolsets=`, avoid `all`. Auth: OAuth > PAT/SAT bearer > API+app keys (app-key scopes `metrics_read`, `monitors_read`, `logs_read_data`, `apm_read`). Never echo keys; use env substitution. |
| PagerDuty | PagerDuty remote MCP (`https://mcp.pagerduty.com/mcp`) | https://support.pagerduty.com/main/docs/pagerduty-mcp-server · archived local: https://github.com/PagerDuty/pagerduty-mcp-server | Local server is read-only unless started with `--enable-write-tools` (do not add it). Remote: use a read-only user/OAuth scope. |
| Opsgenie | No official MCP server found | — | Use the REST API with a read-only API key (`pagerduty-opsgenie` skill). Opsgenie support ends 2027-04-05. |
| Terraform | HashiCorp Terraform MCP server | https://github.com/hashicorp/terraform-mcp-server | Pin the image version and set `--toolsets=registry` (docs say the default is all toolsets; tool names change between versions). Registry lookups are read-only. With `TFE_TOKEN` set, `create_run` (defaults to plan_and_apply) and the workspace, variable, varset, team and tag tools **write**, even with `ENABLE_TF_OPERATIONS` off; plan/state read tools can expose secrets. **Never set `ENABLE_TF_OPERATIONS=true`** (enables apply, destroy, force-unlock, auto_approve). The server may send Terraform data to the LLM. (awslabs and Azure Terraform MCP servers are deprecated.) |
| AWS | AWS API MCP server (awslabs) | https://github.com/awslabs/mcp (`src/aws-api-mcp-server`) | `READ_OPERATIONS_ONLY=true`; optionally `REQUIRE_MUTATION_CONSENT=true`. IAM `ReadOnlyAccess`-style role is the real control. |
| Azure | Azure MCP Server (`@azure/mcp`) | https://github.com/microsoft/mcp (`servers/Azure.Mcp.Server`) | Pin the version (`@azure/mcp@3.0.0`; new majors add write tools), start with `server start --read-only`, and limit tools with repeatable `--namespace` (e.g. `monitor`, `aks`, resource health — check names with `npx -y @azure/mcp@3.0.0 tools list`). Optionally `AZURE_MCP_COLLECT_TELEMETRY=false`. Roles: Reader, Log Analytics Reader, Cost Management Reader, AKS Cluster User Role (cluster scope); never Contributor/Owner. `--read-only` is defense in depth, not a guarantee. |
| Google Cloud | gcloud MCP, observability MCP (local); Google remote MCP servers | https://github.com/googleapis/gcloud-mcp · https://github.com/google/mcp · https://docs.cloud.google.com/mcp | `run_gcloud_command` runs **any** gcloud command the caller is allowed to (minus a fixed default denylist): pass `-c /abs/config.json` with a read-only **allowlist** (example below). The **storage** and **backupdr** servers include delete/restore tools — disable or gate them; the observability server is list/get only. Remote servers use IAM (`roles/mcp.toolUser`). Credentials: ADC or `--impersonate-service-account` to a viewer SA; never create/download keys. Roles: `roles/logging.viewer`, `roles/monitoring.viewer`, `roles/recommender.computeViewer`, plus one viewer role per service used (e.g. `roles/container.viewer`, `roles/run.viewer`, `roles/cloudsql.viewer`, `roles/compute.viewer`). Add `roles/logging.privateLogViewer` only when Data Access logs are needed. |
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

## Datadog setup details

- Use the endpoint for your site (`mcp.datadoghq.eu`, `mcp.us3.datadoghq.com`, …); set `DD_SITE` for API calls to avoid the wrong region.
- Writes needing approval: `POST /api/v1/monitor`, downtimes, mute/unmute, SLO create/update, incidents, events. Logs/spans search POSTs are read-only.
- Rate limits: watch `X-RateLimit-*` headers; back off on `429`. Cost: short windows, small `page.limit`.

## Kubernetes setup details

`k8s-mcp.toml` (genuine config example):

```toml
read_only = true

[[denied_resources]]
group = ""
version = "v1"
kind = "Secret"
```

Claude Code deny rules for Kubernetes and Terraform (in `.claude/settings.json` `permissions.deny`; the `mcp__<server-name>__` prefix depends on your server name; verify exact tool names with `/mcp`):

```json
{
  "permissions": {
    "deny": [
      "mcp__kubernetes__resources_delete",
      "mcp__kubernetes__resources_create_or_update",
      "mcp__kubernetes__resources_scale",
      "mcp__kubernetes__pods_exec",
      "mcp__kubernetes__pods_delete",
      "mcp__kubernetes__pods_run",
      "mcp__kubernetes__helm_install",
      "mcp__kubernetes__helm_uninstall",
      "mcp__terraform__create_run",
      "mcp__terraform__action_run",
      "mcp__terraform__create_workspace",
      "mcp__terraform__update_workspace",
      "mcp__terraform__force_unlock_workspace"
    ]
  }
}
```

## Google Cloud setup details

gcloud MCP read-only allowlist (`config.json`, passed with `-c`; use `allow` or `deny`, not both; the default denylist always applies):

```json
{
  "allow": [
    "config list",
    "projects describe",
    "logging read",
    "monitoring policies list",
    "container clusters list",
    "container clusters describe",
    "compute instances list",
    "compute instance-groups managed list-instances",
    "compute regions describe",
    "compute disks list",
    "run services list",
    "run services describe",
    "sql instances list",
    "sql instances describe",
    "sql backups list",
    "recommender recommendations list"
  ]
}
```

## Example `.mcp.json` (read-only)

Genuine config example. Replace placeholders; keep secrets in env vars.

```json
{
  "mcpServers": {
    "kubernetes": { "command": "npx", "args": ["-y", "kubernetes-mcp-server@<pinned-version>", "--config", "/path/to/k8s-mcp.toml"] },
    "grafana": {
      "command": "uvx", "args": ["mcp-grafana", "--disable-write"],
      "env": { "GRAFANA_URL": "https://grafana.example.com", "GRAFANA_SERVICE_ACCOUNT_TOKEN": "${GRAFANA_SA_TOKEN}" }
    },
    "dynatrace": {
      "command": "npx", "args": ["-y", "@dynatrace-oss/dynatrace-mcp-server@latest"],
      "env": { "DT_ENVIRONMENT": "https://<env-id>.apps.dynatrace.com", "DT_PLATFORM_TOKEN": "${DT_PLATFORM_TOKEN}", "DT_GRAIL_QUERY_BUDGET_GB": "50" }
    },
    "datadog": { "type": "http", "url": "https://mcp.datadoghq.com/api/unstable/mcp-server/mcp" },
    "pagerduty": { "type": "http", "url": "https://mcp.pagerduty.com/mcp" },
    "aws-api": {
      "command": "uvx", "args": ["awslabs.aws-api-mcp-server@latest"],
      "env": { "AWS_REGION": "us-east-1", "READ_OPERATIONS_ONLY": "true", "REQUIRE_MUTATION_CONSENT": "true" }
    },
    "azure": { "command": "npx", "args": ["-y", "@azure/mcp@3.0.0", "server", "start", "--read-only", "--namespace", "monitor", "--namespace", "aks"], "env": { "AZURE_MCP_COLLECT_TELEMETRY": "false" } },
    "terraform": { "command": "docker", "args": ["run", "-i", "--rm", "hashicorp/terraform-mcp-server:<pinned-version>", "--toolsets=registry"] }
  }
}
```

The `dynatrace` entry uses the deprecated local server; prefer Dynatrace for AI + `dtctl` or the Remote MCP Server. Check each server's README for current auth options (OAuth vs. tokens) and env var names before use; they change often.

## Extra guardrails

- Deny write tools in Claude Code permissions as a second layer (see Kubernetes example above); tool names come from `/mcp`.
- Separate prod and non-prod servers/credentials; name them clearly (`kubernetes-prod`).
- Audit: most vendors log API calls; tag the MCP identity so its actions are traceable.
