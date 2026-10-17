# HashiCorp Terraform MCP server: safe configuration

Official server: https://github.com/hashicorp/terraform-mcp-server · Reference: https://developer.hashicorp.com/terraform/mcp-server/reference

## Recommended read-only config (registry only)

```json
{
  "mcpServers": {
    "terraform": {
      "command": "docker",
      "args": ["run", "-i", "--rm", "hashicorp/terraform-mcp-server:<pinned-version>", "--toolsets=registry"]
    }
  }
}
```

Claude Code CLI equivalent:

```bash
claude mcp add terraform -s project -t stdio -- docker run -i --rm hashicorp/terraform-mcp-server:<pinned-version> --toolsets=registry
```

Why:

- **Pin the image tag.** Tool names change between releases (for example `search_providers` became `search_provider_docs`), which breaks deny rules and instructions.
- **Set `--toolsets` explicitly.** The reference says: "When you omit this flag, the server uses `all`." (The source code's default looks like `registry`; don't rely on either.)
- **No `TFE_TOKEN`.** Without it, the `terraform` and `registry-private` toolsets aren't registered.
- **Never set `ENABLE_TF_OPERATIONS=true`.** It turns on `action_run` (apply, discard, cancel), `force_unlock_workspace`, the delete tools, and the `auto_approve` / `is_destroy` run options.

## If you need HCP Terraform read access

- Use a token for a team limited to **read** workspace access (access levels: `read`, `plan`, `write`, `admin`, `custom`). The token's permissions are the real control; tool filtering is a second layer.
- Prefer `--tools=` with an explicit read list over `--toolsets=terraform`, for example:
  `--tools=list_workspaces,get_workspace_details,list_runs,get_run_details,get_plan_details,get_plan_logs`
- **These are writes even with `ENABLE_TF_OPERATIONS` unset:** `create_run` (default type `plan_and_apply`), `create_workspace`, `create_no_code_workspace`, `update_workspace`, `create_workspace_variable`, `update_workspace_variable`, `create_variable_set`, `create_variable_in_variable_set`, `delete_variable_in_variable_set`, `attach_/detach_variable_set_*`, `create_workspace_tags`, `attach_policy_set_to_workspaces`, `create_project`, `create_team`, `add_team_member`, `grant_team_access`.
- **These reads can expose secrets:** `get_plan_json_output`, `get_state_version`, `list_workspace_variables`, `get_workspace_details` (variables), `get_plan_logs`, `get_apply_logs`.
- Streamable-HTTP deployments: TLS, `MCP_ALLOWED_ORIGINS`, `MCP_ORGANIZATION_ALLOWLIST`; never put tokens in query strings (README "Security Considerations").
- The README warns: "the MCP server may expose certain Terraform data to the MCP client and LLM."

## Claude Code permission layer

Add deny rules for write tools (check the exact names with `/mcp`; the prefix depends on the server name):

```json
{ "permissions": { "deny": [
  "mcp__terraform__create_run", "mcp__terraform__action_run",
  "mcp__terraform__create_workspace", "mcp__terraform__update_workspace",
  "mcp__terraform__force_unlock_workspace", "mcp__terraform__delete_workspace_safely",
  "mcp__terraform__create_workspace_variable", "mcp__terraform__update_workspace_variable",
  "mcp__terraform__grant_team_access"
] } }
```

## Deprecated alternatives (don't use)

- `awslabs.terraform-mcp-server`: deprecated March 2026 in favor of the HashiCorp server: https://github.com/awslabs/mcp/discussions/2615
- `Azure/azure-terraform-mcp-server`: archived and deprecated; moved into Azure MCP Server: https://github.com/Azure/azure-terraform-mcp-server
