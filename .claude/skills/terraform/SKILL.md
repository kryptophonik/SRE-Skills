---
name: terraform
description: "Terraform adapter for safe infra changes: fmt/validate, plan review (destroys, replacements, drift), state inspection, revert-and-plan instead of rollback, gated apply. Uses the terraform CLI and the HashiCorp Terraform MCP server (registry and HCP Terraform) read-only by default. Use for any Terraform change, drift check, or infra rollback. Process from change-safety."
---

# Terraform

## Safety gates (REQUIRED)

Follow [sre-safety-gates](../sre-safety-gates/SKILL.md): read-only first; explicit approval before any prod change, MCP write, or external post. `apply`, `destroy`, `import`, `state mv/rm`, `force-unlock`, and HCP Terraform run actions are writes.

Process skill: `change-safety` (risk score, rollout, verification). Remediation reference: `sre-remediation-actions`.

## Read-only workflow

```bash
terraform fmt -check -recursive
terraform init -input=false
terraform validate
terraform plan -input=false -out=tfplan
terraform show -no-color tfplan            # human review
terraform show -json tfplan > tfplan.json  # machine review
terraform state list
terraform state show <address>
terraform plan -refresh-only               # drift check, changes nothing
```

## Plan review checklist

- Count of create / update / **destroy** / **replace** (`-/+`). Any destroy or replace of stateful resources (DBs, volumes, buckets, DNS zones, KMS keys) = high risk; stop and ask.
- Unexpected resources in the plan (drift, wrong workspace, wrong account/subscription/project).
- Sensitive values: never print; `terraform show` masks them, `-json` may not.
- Provider/module version changes.

```bash
# Destroys and replacements from the JSON plan
jq -r '.resource_changes[] | select(.change.actions | index("delete")) | "\(.change.actions|join(",")) \(.address)"' tfplan.json
```

## Rolling back

There is no `terraform rollback`.

1. `git revert <commit>` (or check out the last good config).
2. `terraform plan -out=tfplan` and review — reverting does not undo destroyed data.
3. Apply only after approval: `terraform apply tfplan`.

## Guardrails

- Apply only a saved, reviewed plan file; never `-auto-approve` in prod.
- Use `lifecycle { prevent_destroy = true }` on critical stateful resources.
- Use remote state with locking; `force-unlock` only after confirming no run is active.

## Output

- Plan summary (adds/changes/destroys, risky resources), drift findings, and the exact apply command awaiting approval
