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

Sensitive values: never print. `terraform show` masks only values **marked** sensitive; `show -json`, `state show` (unmarked attributes), `output -json/-raw`, `state pull`, and the plan/state files expose them in plain text. Never commit, upload or paste plan or state files. Use `bash scripts/plan-risk.sh` for machine review. See [references/secrets-exposure.md](references/secrets-exposure.md).

## Confirm the target first

```bash
# run from this skill folder (the one containing SKILL.md)
bash scripts/preflight.sh -C <root-module-dir>   # version, workspace, backend type, lock file, risky env (names only)
terraform -chdir=<root-module-dir> workspace show
# plus the provider's own identity check, e.g. `aws sts get-caller-identity`, `az account show`, `gcloud config list`
```

## Plan review (read-only, one workflow)

Use for any change, drift fix or rollback before apply. It never applies. Every plan in this skill goes to one private path, `"$P"`, outside the repo: plan files hold secrets in clear text, so never commit, upload or paste them.

```bash
P="$(mktemp -d)/tfplan"                                                  # the one plan path for this session
bash scripts/tf-readonly.sh -C <root-module-dir> fmt
bash scripts/tf-readonly.sh -C <root-module-dir> init                   # read-only flags forced; the lock file isn't rewritten
bash scripts/tf-readonly.sh -C <root-module-dir> validate
bash scripts/tf-readonly.sh -C <root-module-dir> plan -out="$P"
bash scripts/tf-readonly.sh -C <root-module-dir> show "$P"               # human review (masks values marked sensitive)
bash scripts/plan-risk.sh -C <root-module-dir> "$P"                      # machine review without values; exit 3 = approval required
terraform -chdir=<root-module-dir> state list
```

`tf-readonly.sh` forces the read-only flags (and `-no-color` on validate, fmt, init, plan and show, so pasted output has no ANSI codes) and refuses writes. `terraform -chdir=<root-module-dir> state show '<address>'` prints attributes not marked sensitive in clear text; quote the address and don't paste the output.

1. Confirm the workspace and account match the intended environment. If anything looks off, stop.
2. `plan-risk.sh` counts create/update/delete/replace/forget, lists deletes, replaces (with forcing attribute paths), imports, moved and removed, sensitive attribute paths changed, output changes and drift, and never prints values. Treat **any** delete, replace, forget, import, errored or incomplete plan as high risk.
3. Check replace reasons (`forced by:` paths, `action_reason`), unexpected resources, drift seen during refresh, and provider or module version changes.
4. Report sensitive changes as attribute **paths** only.
5. **Stateful delete or replace** (databases, volumes, buckets, DNS zones, KMS keys, queues): stop. Don't propose an apply. Find out why (a removed block, a renamed address that needs a `moved` block, a forcing attribute, the wrong workspace or state) and report the cause and the config fix. The fix gets its own new plan review.
6. Otherwise, write the proposal: plan summary, risk, reversibility, rollback, and the plan file path. Then **wait for explicit approval of that exact plan file.**

## Apply the approved plan

Only after step 6 of the plan review and explicit approval. A saved plan applies **without a prompt**. Never `-auto-approve`, never a plain `apply` without the plan file (it re-plans and skips the review).

**Gate: approval required.**

```bash
terraform -chdir=<root-module-dir> apply "$P"
```

If the state changed since the plan, Terraform rejects the stale plan: run the plan review again and get approval again. A failed apply isn't rolled back automatically, so stop and report. Afterwards, check that `bash scripts/drift-check.sh -C <root-module-dir>` exits 0 and the service metrics are healthy, then delete the plan file and its folder (this fails safely if `$P` isn't set in this shell): `rm -f -- "${P:?plan path not set}" && rmdir -- "$(dirname "$P")"`.

## Drift check

```bash
bash scripts/drift-check.sh -C <root-module-dir> [-- -var-file=<env>.tfvars]
echo "exit=$?"   # 0 = no drift, 1 = error, 2 = drift detected
```

The script refuses `-lock=false`, `-target`, `-replace`, `-destroy`, `-refresh=false` and `-auto-approve`, keeps the state lock, and deletes its temporary plan. Detecting drift is read-only; never use `terraform refresh` (= `apply -refresh-only -auto-approve`).

- **0:** no drift. Record the time and workspace.
- **2:** for each drifted address find the cause (incident fix, console change, another tool, provider default), then propose one of: (a) change the config to match reality, then run a plan review; (b) revert reality with a normal plan review and apply; (c) accept reality into state with `terraform -chdir=<root-module-dir> plan -refresh-only -out="$P"`, reviewed like any plan, then applied through Apply the approved plan (it writes state). The script prints these options. Never propose (c) when the drift list shows `delete` (the provider reports the object as gone; hashicorp/local also does this when a file's content changed): accepting it removes the resource from state, so Terraform stops tracking it. The script says "(c) NOT OFFERED" in that case; use (b) to recreate it or (a) to remove it from the config on purpose.
- **1:** report the diagnostics (credentials, lock held, provider error). Don't retry with `-lock=false`.

## Rolling back

There is no `terraform rollback`.

1. `git revert <commit>` (or check out the last good config).
2. Run the plan review. Reverting doesn't bring back destroyed data, and a stateful delete or replace in the revert plan stops at step 5 like any other.
3. Apply through Apply the approved plan, after explicit approval only.

## Guardrails

- Apply only a saved, reviewed plan file, after explicit approval, in every environment. Never `-auto-approve`.
- `lifecycle { prevent_destroy = true }` on critical stateful resources. It **doesn't** protect a resource whose block is removed from config.
- Remote state with locking. `terraform force-unlock LOCK_ID` only with explicit approval, after confirming no run is active, and never `-force`.
- **Opt-in second layer (not enabled by default):** [hooks/terraform-guard.sh](hooks/terraform-guard.sh) (PreToolUse: denies auto-approve, destroy, refresh, plan-less apply; asks for saved-plan apply, state surgery, import, force-unlock) and the rules in [assets/settings.example.json](assets/settings.example.json). They match strings: a guardrail, not a sandbox.
- MCP: [references/mcp-server-safety.md](references/mcp-server-safety.md).
- Tests: `bash tests/run-tests.sh` (throwaway `terraform_data` config). Requires bash 3.2+, jq, terraform 1.16+.

If terraform is not available, output the commands for the human and stop.

## Output

- Target confirmed (workspace + identity), plan summary (adds/changes/destroys/replaces, risky resources, sensitive paths), drift result with exit code, likely cause and proposed option. For a stateful delete or replace: the cause and the config fix, with no apply proposed. Otherwise: the plan file path awaiting approval
