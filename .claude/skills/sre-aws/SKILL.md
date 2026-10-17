---
name: sre-aws
description: "Use when the system runs on AWS: Health, CloudWatch metrics and Logs Insights, EC2/EKS/RDS/ELB/ASG/ECS status, CloudTrail, quotas. Read-only profile via AWS CLI or MCP; writes need approval."
---

# AWS

## Safety gates (REQUIRED)

1. Read-only diagnosis first.
2. Propose each change with risk (low/med/high) and reversibility.
3. Wait for explicit human approval before any prod-changing command, MCP write tool, or external post.
4. Act only as approved, verify, and stop and escalate if anything gets worse.

Full rules: [sre-safety-gates](../sre-safety-gates/SKILL.md). Read-only MCP setup: [sre-safety-gates/references/mcp.md](../sre-safety-gates/references/mcp.md).

Process skills: `sre-engineer`, `sre-k8s-triage` (EKS), `sre-dr-backup-test`, `sre-capacity-planning`, `sre-cloud-cost-review`, `sre-security-incident-triage`.

## Rules

- **Every command carries `--profile <profile> --region <region>`** (or `AWS_PROFILE`/`AWS_REGION` set and confirmed). Nothing depends on local defaults.
- **Bound pagination:** add `--max-items <n>` to list/describe calls.
- **Writes needing approval:** any `create-*`, `update-*`, `modify-*`, `delete-*`, `put-*`, `start-*`/`stop-*`/`reboot-*`, `terminate-*`, `restore-*`, `register-*`/`deregister-*`, `attach-*`/`detach-*`, `tag-*`/`untag-*`, `set-desired-capacity`; also `logs start-query` (cost) and `eks update-kubeconfig` (local write).
- **IAM:** `ViewOnlyAccess` (metadata only) plus the extras in [references/readonly-iam-policy.json](references/readonly-iam-policy.json) (`ce:GetCostAndUsage`, `health:Describe*`, `logs:StartQuery`/`GetQueryResults`/`FilterLogEvents`, `sts:GetCallerIdentity`) and its explicit **Deny** for secret/data reads (`secretsmanager:GetSecretValue`, `ssm:GetParameter*`, `s3:GetObject`, `kms:Decrypt`). Do not grant `logs:StartLiveTail` (streams). Avoid `ReadOnlyAccess`: it can read data.
- **Cost:** CloudWatch metric API calls are billed per request; Logs Insights bills per GB scanned; Cost Explorer bills per request. Keep windows narrow.

## Always first

```bash
aws sts get-caller-identity --profile <profile>
aws configure list --profile <profile>           # shows region source; `aws configure get region` ignores AWS_REGION/--region
echo "${AWS_REGION:-$AWS_DEFAULT_REGION}"
```

## Health and status (read-only)

AWS Health API needs Business Support+, Enterprise, or Unified Operations (or legacy Business / Enterprise On-Ramp / Enterprise where those still apply); otherwise `SubscriptionRequiredException`. The active endpoint is us-east-1 (us-east-2 is passive, eventually consistent); on failover find the active Region with `dig global.health.amazonaws.com`. Org-wide: `aws health describe-events-for-organization` (needs organizational view enabled from the management or delegated-admin account).

```bash
aws health describe-events --profile <profile> --region us-east-1 --filter eventStatusCodes=open --max-items 50
aws ec2 describe-instance-status --profile <profile> --region <region> --include-all-instances --filters Name=instance-status.status,Values=impaired --max-items 100
aws autoscaling describe-auto-scaling-groups --profile <profile> --region <region> --auto-scaling-group-names <asg>
aws elbv2 describe-target-health --profile <profile> --region <region> --target-group-arn <arn>
aws rds describe-db-instances --profile <profile> --region <region> --db-instance-identifier <db> --query 'DBInstances[0].DBInstanceStatus'
aws eks describe-cluster --profile <profile> --region <region> --name <cluster> --query 'cluster.status'
```

Kubeconfig (local write: edits `~/.kube/config` and can switch your current context; use an alias, then confirm):

```bash
aws eks update-kubeconfig --profile <profile> --region <region> --name <cluster> --alias <cluster>-ro --kubeconfig ./kubeconfig-<cluster>   # per-incident file
kubectl config current-context
```

## CloudWatch (read-only; billed per request / per GB)

```bash
aws cloudwatch describe-alarms --profile <profile> --region <region> --state-value ALARM --max-items 100
aws cloudwatch get-metric-statistics --profile <profile> --region <region> --namespace AWS/ApplicationELB --metric-name HTTPCode_Target_5XX_Count \
  --dimensions Name=LoadBalancer,Value=<app/name/id> --start-time <ISO8601> --end-time <ISO8601> --period 300 --statistics Sum
aws logs tail /aws/lambda/<fn> --profile <profile> --region <region> --since 30m --filter-pattern "?ERROR ?Exception" | head -200   # filtered and capped; never --follow unattended
# Logs Insights: one log group, narrow window (billed per GB scanned)
aws logs start-query --profile <profile> --region <region> --log-group-name <group> --start-time <epoch> --end-time <epoch> \
  --query-string 'fields @timestamp, @message | filter @message like /ERROR/ | sort @timestamp desc | limit 50'
aws logs get-query-results --profile <profile> --region <region> --query-id <query-id>
aws logs stop-query --profile <profile> --region <region> --query-id <query-id>     # stop a runaway query
```

## Common remediations (WRITE — approval required)

| Action | Command | Risk | Reversible |
|---|---|---|---|
| Scale ASG | `aws autoscaling set-desired-capacity --profile <profile> --region <region> --auto-scaling-group-name <asg> --desired-capacity <n>` | low | yes |
| Deregister bad target | `aws elbv2 deregister-targets --profile <profile> --region <region> --target-group-arn <arn> --targets Id=<id>` | low | yes |
| Reboot RDS with failover (Multi-AZ only; causes a brief outage) | `aws rds reboot-db-instance --profile <profile> --region <region> --db-instance-identifier <db> --force-failover` | high | no |
| Roll back ECS service | `aws ecs update-service --profile <profile> --region <region> --cluster <c> --service <s> --task-definition <family:prev-rev>` | med | yes |

## Output

- Profile, account and region confirmed; findings with commands used; proposed actions with risk/reversibility
