---
name: terraform
description: "Terraform adapter for safe infra changes: confirm target, fmt/validate, saved-plan review (destroys, replacements, drift), state inspection without leaking secrets, revert-and-plan instead of rollback, and gated apply of the exact reviewed plan. Uses the terraform CLI and the HashiCorp Terraform MCP server (registry toolset, pinned) read-only by default. Use for any Terraform change, drift check, or infra rollback. Process from change-safety."
---

# Terraform

## Safety gates (REQUIRED)

Follow [sre-safety-gates](../sre-safety-gates/SKILL.md): read-only first; explicit approval before any prod change, MCP write, or external post.

Process skill: `change-safety` (risk score, rollout, verification). Remediation reference: `sre-remediation-actions`.

## Writes (each needs explicit approval)

`apply` (with or without a plan file), `destroy` and `plan -destroy`, `-replace`, `taint`/`untaint`, `import` (command and `import` blocks), `moved`/`removed` blocks, `state mv/rm/push/replace-provider`, `apply -refresh-only`, `refresh`, `workspace new/select/delete`, `init -migrate-state/-reconfigure/-force-copy/-upgrade`, `force-unlock`, and HCP Terraform run actions.

**Emergency-only, with explicit approval:** `-lock=false`, `-target`. **Never:** `-auto-approve` or apply without a reviewed plan file in any environment without explicit approval; `force-unlock -force`.

## Secrets rule

Plan files, state files, `terraform show -json`, `terraform state show`, and `terraform output -json/-raw` expose sensitive values in **plain text**. Never commit, upload, paste, or print them. Process JSON only with `jq` filters that drop values. Delete the plan file and its JSON after apply. `terraform show -no-color <plan-file>` masks sensitive values.

## Confirm the target first

```bash
terraform workspace show
# plus the provider's own identity check, e.g. `aws sts get-caller-identity`, `az account show`, `gcloud config list`
```

## Read-only workflow

```bash
terraform fmt -check -recursive
terraform init -input=false -lockfile=readonly     # plain init can rewrite .terraform.lock.hcl
terraform validate
terraform plan -input=false -out=<plan-file>       # plan file holds secrets: never commit/upload/paste; delete after apply
terraform show -no-color <plan-file>               # human review, secrets masked
terraform show -json <plan-file> > <plan-file>.json   # plain-text secrets: process with jq only, never print
terraform state list
terraform state show '<address>'                   # quote for for_each/count addresses; can print secrets
```

## Drift check

```bash
terraform plan -refresh-only -input=false -detailed-exitcode -no-color
```

Exit `0` = no drift, `1` = error, `2` = drift. Never run `terraform apply -refresh-only` or `terraform refresh` without approval: both write state, and `refresh` auto-approves.

## Plan review checklist

- Count of create / update / **destroy** / **replace** (`-/+`). Any destroy or replace of stateful resources (DBs, volumes, buckets, DNS zones, KMS keys) = high risk; stop and ask.
- Unexpected resources (drift, wrong workspace, wrong account/subscription/project).
- Provider/module version changes.

```bash
# Destroys and replacements from the JSON plan (prints addresses only)
jq -r '.resource_changes[] | select(.change.actions | index("delete")) | "\(.change.actions|join(",")) \(.address)"' <plan-file>.json
```

## Rolling back

There is no `terraform rollback`.

1. `git revert <commit>` (or check out the last good config).
2. `terraform plan -input=false -out=<plan-file> && terraform show -no-color <plan-file>` and review — reverting does not restore destroyed data.
3. Get explicit approval for that exact plan.
4. `terraform apply <plan-file>` — a saved plan applies with **no prompt**, so approval must come first. Re-plan if state changed since review.

## Guardrails

- Apply only the exact saved plan that was reviewed and approved.
- `lifecycle { prevent_destroy = true }` on critical stateful resources — it does **not** help if the resource block is removed from config.
- Remote state with locking. `terraform force-unlock <LOCK_ID>` only with human approval after confirming no run is active; never `-force`.

## Output

- Target confirmed (workspace + identity), plan summary (adds/changes/destroys, risky resources), drift result with exit code, and the exact `terraform apply <plan-file>` awaiting approval
