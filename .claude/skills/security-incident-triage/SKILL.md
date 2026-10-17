---
name: security-incident-triage
description: "First-response triage for suspected security incidents: leaked credentials, suspicious access, compromised host or container, unexpected infra changes. Preserves evidence, proposes containment only with approval, and hands off to the security team. Uses read-only audit logs (CloudTrail, Azure Activity Log, GCP Audit Logs, Kubernetes audit) when available. Use when compromise is suspected."
---

# Security Incident Triage

## Safety gates (REQUIRED)

Follow [sre-safety-gates](../sre-safety-gates/SKILL.md): read-only first; explicit approval before any prod change, MCP write, or external post.

**Hand off early.** Notify the security team / security on-call as soon as compromise is plausible. They own the investigation; SRE supports.

## Do not

- Do not restart, delete, re-image, or scale down suspected hosts/pods before evidence is captured and security agrees — it destroys evidence.
- Do not paste secrets, tokens, or customer data into chat, tickets, or AI tools. Reference them by name/ID.
- Do not tip off a suspected insider in public channels; use a private channel.
- Do not post externally; legal/privacy own customer and regulator notices.

## Workflow

1. **Open a private channel**, page security on-call, start a timeline (UTC).
2. **Scope (read-only):** what is suspected, which accounts/keys/hosts, first and last seen.
3. **Preserve evidence:** snapshot disks/volumes, export audit logs, save pod specs and logs, record running processes — through approved tooling.
4. **Propose containment** (with security, approval required): rotate/disable leaked keys, isolate host (security group / network policy), revoke sessions, block IPs. Prefer isolate over delete.
5. **Monitor** for continued activity after containment.
6. **Hand off** with evidence locations and timeline; support recovery.
7. **Postmortem** with security (`sre-postmortem-templates`), keeping sensitive details restricted.

## Read-only audit queries

```bash
# AWS: recent activity for an access key
aws cloudtrail lookup-events --lookup-attributes AttributeKey=AccessKeyId,AttributeValue=<AKIA...> --max-results 50
# Azure: activity log for a resource group, last 24h
az monitor activity-log list --resource-group <rg> --subscription <subscription-id> --offset 24h -o table
# GCP: admin activity audit log
gcloud logging read 'logName:"cloudaudit.googleapis.com%2Factivity"' --freshness=1d --limit=50
# Kubernetes: who can do what
kubectl auth can-i --list --as=<user> -n <ns>
```

## Containment actions (WRITE — security + IC approval)

| Action | Risk | Reversible |
|---|---|---|
| Deactivate AWS access key: `aws iam update-access-key --access-key-id <id> --status Inactive --user-name <user>` | med | yes |
| Isolate pod: apply deny-all NetworkPolicy selecting the pod | med | yes |
| Cordon node: `kubectl cordon <node>` | low | yes |
| Rotate secret in secret manager and redeploy consumers | med | partial |

## Output

- Security triage record: timeline, scope, evidence locations, containment taken (with approver), handoff to security
