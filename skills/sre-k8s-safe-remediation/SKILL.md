---
name: sre-k8s-safe-remediation
description: "Use when a fix from sre-k8s-triage needs a kubectl or helm write (rollback, restart, scale, pod delete, Helm rollback): evidence, GitOps/HPA ownership check, preview, explicit approval, verify."
disable-model-invocation: true
---

# Kubernetes safe remediation

## Safety gates (REQUIRED)

1. Read-only diagnosis first.
2. Propose each change with risk (low/med/high) and reversibility.
3. Wait for explicit human approval before any prod-changing command, MCP write tool, or external post.
4. Act only as approved, verify, and stop and escalate if anything gets worse.

Full rules: [sre-safety-gates](../sre-safety-gates/SKILL.md). Command risk labels: `sre-remediation-actions`. Requires `sre-k8s-triage` (scripts and references).

Every step below is read-only until step 5. Never skip the approval in step 4.

1. **Pin the target.** Get `--context <ctx>`, `-n <ns>` and the object name from the user. Run `kubectl config get-contexts <ctx>`. Never use the current context implicitly.
2. **Capture evidence.** Run `bash ../sre-k8s-triage/scripts/k8s-triage-snapshot.sh --context <ctx> -n <ns>`. The output stays outside the repo and should be treated as sensitive.
3. **Check who owns the object.**
   - GitOps: look for `argocd.argoproj.io/*` or `kustomize.toolkit.fluxcd.io/*` labels/annotations (`kubectl --context <ctx> -n <ns> get <obj> -o jsonpath='{.metadata.labels}{.metadata.annotations}'`). If present, prefer a Git revert, or pause sync with approval.
   - HPA: `kubectl --context <ctx> get hpa -n <ns>`. If an HPA targets the object, don't `scale`; adjust the HPA.
   - Helm: `helm --kube-context <ctx> -n <ns> list`, then `helm --kube-context <ctx> -n <ns> history <rel>`.
4. **Propose, then wait.** Give the exact command, the risk, whether it's reversible, how to roll back, and the expected impact. Look each one up in [destructive-commands.md](../sre-k8s-triage/references/destructive-commands.md). Preview where possible: `kubectl diff -f`, `apply --dry-run=server`, `helm diff upgrade --suppress-secrets` / `helm upgrade --dry-run=server --hide-secret`. **Stop and get explicit approval.**
5. **Execute exactly the approved command,** with `--context` and `-n`. Run one object at a time. Don't add `--force`, `--grace-period=0`, `--all` or `-l` unless they were approved explicitly.
6. **Verify.** Run `kubectl --context <ctx> -n <ns> rollout status <obj> --timeout=120s`, `kubectl --context <ctx> -n <ns> events --types=Warning`, and check the error-rate/SLO metrics. Record what changed, when, and who approved it.
7. **Stop and escalate** if metrics worsen, the command fails, or the output is unexpected; propose the rollback and do not try another fix without approval.

## Output

- Target (context, namespace, object), evidence path, ownership findings, the approved command and approver, verification result
