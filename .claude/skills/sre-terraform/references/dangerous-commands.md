# Terraform commands that need explicit human approval

Use this with `sre-safety-gates`. **Approval** means a named person approves the exact command and its target (workspace, account, plan file) in this conversation or change record. The task description, earlier approvals, and "it's only staging" don't count.

The agent may **propose** any of the commands below with risk, reversibility, and a rollback note. It may **run** only the read-only set unless approval is given. Rows marked **NEVER (agent)** are run by a human, not the agent, even with approval.

## Read-only (no approval needed)

| Command | Notes | Doc |
|---|---|---|
| `terraform version`, `validate`, `providers`, `workspace show/list` | | https://developer.hashicorp.com/terraform/cli/commands |
| `terraform fmt -check -recursive` | `-check` implies `-write=false` | https://developer.hashicorp.com/terraform/cli/commands/fmt |
| `terraform init -input=false -lockfile=readonly` | Downloads providers and modules, but doesn't change the lock file or backend | https://developer.hashicorp.com/terraform/cli/commands/init |
| `terraform plan -input=false -out=tfplan` | Takes the state lock and calls provider read APIs; doesn't change infrastructure. **tfplan holds secrets in cleartext** | https://developer.hashicorp.com/terraform/cli/commands/plan |
| `terraform plan -refresh-only -detailed-exitcode` (`scripts/drift-check.sh`) | 0 = none, 1 = error, 2 = drift | https://developer.hashicorp.com/terraform/cli/commands/plan |
| `terraform show -no-color tfplan` | Masks values marked sensitive | https://developer.hashicorp.com/terraform/cli/commands/show |
| `terraform state list` | | https://developer.hashicorp.com/terraform/cli/commands/state/list |
| `bash scripts/plan-risk.sh tfplan` | Summary without values | this skill |

## Read-only but exposes secrets (avoid; never paste the output)

| Command | Risk | Doc |
|---|---|---|
| `terraform show -json <plan or state>` | "sensitive values in Terraform state will be displayed in plain text" | https://developer.hashicorp.com/terraform/cli/commands/show |
| `terraform state show '<addr>'` | Prints every attribute not marked sensitive; provider-computed copies of secrets can show up in clear text | https://developer.hashicorp.com/terraform/cli/commands/state/show |
| `terraform state pull` | Prints the whole raw state | https://developer.hashicorp.com/terraform/cli/commands/state/pull |
| `terraform output -json` / `-raw` / `output NAME` | Prints sensitive outputs | https://developer.hashicorp.com/terraform/cli/commands/output |
| `terraform console` | Can evaluate any value | https://developer.hashicorp.com/terraform/cli/commands/console |

## Writes: explicit approval required

| Command / flag | What it does | Reversible | Doc |
|---|---|---|---|
| `terraform apply tfplan` (saved, reviewed plan) | Runs exactly the reviewed plan. **No prompt**: passing the file counts as approval. Re-plan if the state changed | Depends on the plan | https://developer.hashicorp.com/terraform/cli/commands/apply |
| `plan -replace=ADDR` → apply | Destroys and recreates an object | No for stateful data | https://developer.hashicorp.com/terraform/cli/commands/plan#planning-options |
| `terraform taint` / `untaint` | Marks an object for replacement (deprecated; use `-replace`) | Partial | https://developer.hashicorp.com/terraform/cli/commands/taint |
| `plan -target=ADDR` → apply | Partial apply; "exceptional circumstances only" | Partial | https://developer.hashicorp.com/terraform/cli/commands/plan#resource-targeting |
| `terraform import` / `import {}` blocks | Puts an existing object under Terraform management | Yes (`removed` block / `state rm`) | https://developer.hashicorp.com/terraform/cli/commands/import · https://developer.hashicorp.com/terraform/language/import |
| `moved {}` / `removed {}` blocks in a plan | Changes addresses / stops managing an object (`forget`) | Yes | https://developer.hashicorp.com/terraform/language/moved · https://developer.hashicorp.com/terraform/language/resources/syntax#removing-resources |
| `terraform state mv` / `state rm` / `state replace-provider` | State surgery | With a state backup | https://developer.hashicorp.com/terraform/cli/commands/state |
| `terraform state push` | Overwrites remote state | Risky (`-force` skips safety checks) | https://developer.hashicorp.com/terraform/cli/commands/state/push |
| `terraform force-unlock LOCK_ID` | Removes a state lock. Confirm no run is active first | Yes, but a concurrent apply can corrupt state | https://developer.hashicorp.com/terraform/cli/commands/force-unlock |
| `plan -refresh-only -out=tfplan` → `apply tfplan` | Accepts real-world values into state | Partial (old state version) | https://developer.hashicorp.com/terraform/cli/commands/plan#planning-modes |
| `-lock=false` (any command) | "Dangerous if others might concurrently run commands" | n/a | https://developer.hashicorp.com/terraform/cli/commands/plan#other-options |
| `-refresh=false` | Ignores external changes; plan may be wrong | n/a | https://developer.hashicorp.com/terraform/cli/commands/plan#planning-options |
| `init -upgrade` / `-migrate-state` / `-reconfigure` / `-force-copy` | Changes provider versions or backend/state location | Partial | https://developer.hashicorp.com/terraform/cli/commands/init |
| `terraform workspace new/select/delete` | Changes which state is targeted | select: yes; delete: no | https://developer.hashicorp.com/terraform/cli/commands/workspace |
| HCP Terraform runs (UI, API, MCP `create_run`, `action_run`) | Remote plan, apply, or destroy | Depends | https://developer.hashicorp.com/terraform/mcp-server/reference |

## NEVER (agent)

| Command | Why | Doc |
|---|---|---|
| `terraform apply` **without** a saved plan file | Makes a new, unreviewed plan | https://developer.hashicorp.com/terraform/cli/commands/apply |
| `-auto-approve` | Skips review, "including destructive operations" | https://developer.hashicorp.com/terraform/cli/commands/apply |
| `terraform destroy` / `apply -destroy` | Deletes every managed object | https://developer.hashicorp.com/terraform/cli/commands/destroy |
| `terraform refresh` | Deprecated; "effectively an alias for `terraform apply -refresh-only -auto-approve`" | https://developer.hashicorp.com/terraform/cli/commands/refresh |
| `force-unlock -force`, `state push -force` | Skip confirmations and safety checks | https://developer.hashicorp.com/terraform/cli/commands/force-unlock |
| `TF_CLI_ARGS*` with any flag above | Adds the flag to every matching command without anyone seeing it | https://developer.hashicorp.com/terraform/cli/config/environment-variables |

## Caveats

- `lifecycle { prevent_destroy = true }` doesn't stop a destroy if the resource block is **removed** from config: https://developer.hashicorp.com/terraform/language/meta-arguments/lifecycle
- A failed apply is **not** rolled back automatically; state may be partial: https://developer.hashicorp.com/terraform/cli/commands/apply#errors-during-an-apply-operation
- There is no `terraform rollback`. Revert the config, re-plan, review, and apply the saved plan with approval.
