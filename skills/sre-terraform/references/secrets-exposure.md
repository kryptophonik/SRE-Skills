# Where Terraform exposes secrets, and how to avoid it

Rule: **never print, paste, upload, or commit sensitive values.** Report addresses, attribute names, and counts, not values.

## Leak paths

| Surface | Exposure | Safer alternative | Doc |
|---|---|---|---|
| Saved plan file (`tfplan`) | "If your plan includes any sort of sensitive data, even if obscured in Terraform's terminal output, it will be saved in cleartext in the plan file." | Write it to a private temp dir or a protected CI artifact; delete it after apply; never commit it | https://developer.hashicorp.com/terraform/cli/commands/plan#out-filename |
| `terraform show -json` | "Any sensitive values in Terraform state will be displayed in plain text." | `scripts/plan-risk.sh` (reads JSON in memory and prints no values) | https://developer.hashicorp.com/terraform/cli/commands/show |
| `terraform state show` | Masks attributes the provider marks sensitive. **Other attributes, including provider-computed copies of a secret, print in clear text** (seen in testing: `terraform_data.input` masked, `.output` printed) | `terraform state list`; ask a human to check specific non-secret attributes | https://developer.hashicorp.com/terraform/cli/commands/state/show |
| State file / `state pull` | The full state is stored in plain text | Remote backend with encryption and access control; don't read raw state | https://developer.hashicorp.com/terraform/language/manage-sensitive-data |
| `terraform output -json` / `-raw` | Prints sensitive outputs | Leave outputs alone, or list names via plan-risk.sh | https://developer.hashicorp.com/terraform/cli/commands/output |
| `TF_LOG=DEBUG/TRACE` logs | Provider requests and responses can include secrets | Leave it unset; never share logs | https://developer.hashicorp.com/terraform/internals/debugging |
| `-var 'password=...'` | Shows up in shell history and process lists | `-var-file` (gitignored) or `TF_VAR_*` from a secret manager | https://developer.hashicorp.com/terraform/language/values/variables |
| Human plan output | Masks values marked sensitive; unmarked secrets show | Mark variables and outputs `sensitive = true`; consider `ephemeral = true` (Terraform 1.10+) | https://developer.hashicorp.com/terraform/language/manage-sensitive-data |
| HCP Terraform via MCP | `get_plan_json_output`, `get_state_version`, `list_workspace_variables` can return secret data to the model | Registry-only toolset by default; see mcp-server-safety.md | https://developer.hashicorp.com/terraform/mcp-server/reference |

## Hygiene checklist

- `.gitignore`: `*.tfstate`, `*.tfstate.*`, `tfplan`, `*.tfplan`, `tfplan.json`, `.terraform/`, `*.tfvars` holding secrets. Commit `.terraform.lock.hcl`.
- `scripts/preflight.sh` warns about state and plan files on disk, and about `TF_LOG` or `TF_CLI_ARGS*` (names only).
- Use `sensitive = true` on variables and outputs, and use write-only/ephemeral arguments where the provider supports them.
- In incident notes, write "attribute `password` changed on `<address>`", never the value.
