---
name: sre-terraform
description: "Use for any Terraform change, plan review, drift check or rollback: confirm target, fmt/validate, saved-plan review, state inspection without leaking secrets, gated apply of the reviewed plan."
---

# Terraform

## Safety gates (REQUIRED)

1. Read-only diagnosis first.
2. Propose each change with risk (low/med/high) and reversibility.
3. Wait for explicit human approval before any prod-changing command, MCP write tool, or external post.
4. Act only as approved, verify, and stop and escalate if anything gets worse.

Full rules: [sre-safety-gates](../sre-safety-gates/SKILL.md). Read-only MCP setup: [sre-safety-gates/references/mcp.md](../sre-safety-gates/references/mcp.md).

Process skill: `sre-change-safety` (risk score, rollout, verification). Remediation reference: `sre-remediation-actions`.

## Writes (each needs explicit approval)

`apply`, `destroy` and `plan -destroy`, `import` (command and `import` blocks), `taint`/`untaint`, `-replace`, `-target`, `moved`/`removed` blocks, `state mv/rm/push/replace-provider`, `force-unlock`, `apply -refresh-only`, `terraform refresh`, `-lock=false`, `-refresh=false`, `init -upgrade/-migrate-state/-reconfigure/-force-copy`, `workspace new/select/delete`, and HCP Terraform run/workspace actions. Full tiered list: [references/dangerous-commands.md](references/dangerous-commands.md).

- **Never:** `-auto-approve`, `destroy`, `refresh`, `apply` without a saved plan file, `force-unlock -force`.
- **Only with explicit approval:** everything else in the list above; `-lock=false` and `-target` are emergency-only.

## Secrets rule

Sensitive values: never print. `terraform show` masks only values **marked** sensitive; `show -json`, `state show` (unmarked attributes), `output -json/-raw`, `state pull`, and the plan/state files expose them in plain text. Never commit, upload or paste plan or state files. Use `scripts/plan-risk.sh` for machine review. See [references/secrets-exposure.md](references/secrets-exposure.md).

## Confirm the target first

```bash
S=${CLAUDE_SKILL_DIR}/scripts
$S/preflight.sh -C <root-module-dir>   # version, workspace, backend type, lock file, risky env (names only)
terraform -chdir=<root-module-dir> workspace show
# plus the provider's own identity check, e.g. `aws sts get-caller-identity`, `az account show`, `gcloud config list`
```

## Read-only workflow

```bash
terraform fmt -check -recursive
terraform init -input=false -lockfile=readonly    # don't rewrite the lock file
terraform validate
terraform plan -input=false -out=tfplan           # tfplan holds secrets in cleartext: never commit, upload, or paste it
terraform show -no-color tfplan                   # human review (masks values marked sensitive)
$S/plan-risk.sh tfplan                            # machine review without values; exit 3 = approval required
terraform state list
terraform state show '<address>'                  # quote addresses; prints attributes not marked sensitive in clear text
$S/drift-check.sh                                 # plan -refresh-only -detailed-exitcode: 0 none, 1 error, 2 drift
```

Or run everything through `$S/tf-readonly.sh -C <root-module-dir> <subcommand>`, which forces the read-only flags and refuses writes.

## Plan review

Use for any change before apply. Never applies.

```bash
P="$(mktemp -d)/tfplan"                                      # private path; plan files hold secrets
$S/tf-readonly.sh -C <root-module-dir> init
$S/tf-readonly.sh -C <root-module-dir> validate
$S/tf-readonly.sh -C <root-module-dir> plan -out="$P"
$S/tf-readonly.sh -C <root-module-dir> show -no-color "$P"
$S/plan-risk.sh   -C <root-module-dir> "$P"                  # exit 3 = approval required
```

1. Confirm the workspace and account match the intended environment. If anything looks off, stop.
2. `plan-risk.sh` counts create/update/delete/replace/forget, lists deletes, replaces (with forcing attribute paths), imports, moved and removed, sensitive attribute paths changed, output changes and drift, and never prints values. Treat **any** delete, replace, forget, import, errored or incomplete plan as high risk. For stateful resources (databases, volumes, buckets, DNS zones, KMS keys, queues), stop and ask.
3. Check replace reasons (`forced by:` paths, `action_reason`), unexpected resources, drift seen during refresh, and provider or module version changes.
4. Report sensitive changes as attribute **paths** only.
5. End with the exact command awaiting approval: `terraform -chdir=<root-module-dir> apply <planfile>`. It runs **without a prompt**, so approval comes first. If the state changed, re-plan. Delete the plan file afterward.

## Drift check

```bash
$S/drift-check.sh -C <root-module-dir> [-- -var-file=<env>.tfvars]
echo "exit=$?"   # 0 = no drift, 1 = error, 2 = drift detected
```

The script refuses `-lock=false`, `-target`, `-replace`, `-destroy`, `-refresh=false` and `-auto-approve`, keeps the state lock, and deletes its temporary plan. Detecting drift is read-only; never use `terraform refresh` (= `apply -refresh-only -auto-approve`).

- **0:** no drift. Record the time and workspace.
- **2:** for each drifted address find the cause (incident fix, console change, another tool, provider default), then propose one of: (a) change the config to match reality, then run a Plan review; (b) revert reality by applying the normal plan (approval required); (c) accept into state with `terraform plan -refresh-only -out=tfplan`, review, then `terraform apply tfplan` (approval required; writes state).
- **1:** report the diagnostics (credentials, lock held, provider error). Don't retry with `-lock=false`.

## Rolling back

There is no `terraform rollback`.

1. `git revert <commit>` (or check out the last good config).
2. `terraform plan -input=false -out=tfplan && terraform show -no-color tfplan && $S/plan-risk.sh tfplan`. Reverting doesn't undo destroyed data.
3. After explicit approval only: `terraform apply tfplan`. A saved plan applies **without a prompt**. If the state changed, Terraform rejects the stale plan; re-plan. A failed apply is not rolled back automatically.

## Guardrails

- Apply only a saved, reviewed plan file, after explicit approval, in every environment. Never `-auto-approve`.
- `lifecycle { prevent_destroy = true }` on critical stateful resources. It **doesn't** protect a resource whose block is removed from config.
- Remote state with locking. `terraform force-unlock LOCK_ID` only with explicit approval, after confirming no run is active, and never `-force`.
- **Opt-in second layer (not enabled by default):** [hooks/terraform-guard.sh](hooks/terraform-guard.sh) (PreToolUse: denies auto-approve, destroy, refresh, plan-less apply; asks for saved-plan apply, state surgery, import, force-unlock) and the rules in [assets/settings.example.json](assets/settings.example.json). They match strings: a guardrail, not a sandbox.
- MCP: [references/mcp-server-safety.md](references/mcp-server-safety.md).
- Tests: `${CLAUDE_SKILL_DIR}/tests/run-tests.sh` (throwaway `terraform_data` config). Requires bash 4+, jq, terraform 1.x.

If terraform is not available, output the commands for the human and stop.

## Output

- Target confirmed (workspace + identity), plan summary (adds/changes/destroys/replaces, risky resources, sensitive paths), drift result with exit code, likely cause and proposed option, and the exact `terraform apply <plan-file>` awaiting approval
