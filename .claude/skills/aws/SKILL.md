---
name: aws
description: "AWS adapter for SRE: account/region sanity, service health, CloudWatch metrics and logs, EC2/EKS/RDS/ELB/ASG status, CloudTrail lookups, quotas. Uses the AWS CLI with read-only IAM or the awslabs AWS API MCP server with READ_OPERATIONS_ONLY=true. Use when the system runs on AWS. Writes need approval."
---

# AWS

## Safety gates (REQUIRED)

Follow [sre-safety-gates](../sre-safety-gates/SKILL.md): read-only first; explicit approval before any prod change, MCP write, or external post. Any `create-*`, `update-*`, `modify-*`, `delete-*`, `put-*`, `start/stop/reboot-*`, `set-desired-capacity` call is a write.

Process skills: `sre-engineer`, `k8s-triage` (EKS), `dr-backup-test`, `capacity-planning`, `cloud-cost-review`, `security-incident-triage`.

## Always first

```bash
aws sts get-caller-identity          # which account/role
aws configure get region
```

## Health and status

```bash
aws health describe-events --region us-east-1 --filter eventStatusCodes=open   # needs Business/Enterprise support
aws ec2 describe-instance-status --include-all-instances --filters Name=instance-status.status,Values=impaired
aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names <asg>
aws elbv2 describe-target-health --target-group-arn <arn>
aws rds describe-db-instances --db-instance-identifier <db> --query 'DBInstances[0].DBInstanceStatus'
aws eks describe-cluster --name <cluster> --query 'cluster.status'
aws eks update-kubeconfig --name <cluster>   # writes local kubeconfig only
```

## CloudWatch

```bash
aws cloudwatch describe-alarms --state-value ALARM
aws cloudwatch get-metric-statistics --namespace AWS/ApplicationELB --metric-name HTTPCode_Target_5XX_Count \
  --dimensions Name=LoadBalancer,Value=<app/name/id> --start-time <ISO8601> --end-time <ISO8601> --period 300 --statistics Sum
aws logs tail /aws/lambda/<fn> --since 30m
aws logs start-query --log-group-name <group> --start-time <epoch> --end-time <epoch> \
  --query-string 'fields @timestamp, @message | filter @message like /ERROR/ | sort @timestamp desc | limit 50'
```

## Common remediations (WRITE — approval required)

| Action | Command | Risk | Reversible |
|---|---|---|---|
| Scale ASG | `aws autoscaling set-desired-capacity --auto-scaling-group-name <asg> --desired-capacity <n>` | low | yes |
| Deregister bad target | `aws elbv2 deregister-targets --target-group-arn <arn> --targets Id=<id>` | low | yes |
| Reboot RDS (failover) | `aws rds reboot-db-instance --db-instance-identifier <db> --force-failover` | high | no |
| Roll back ECS service | `aws ecs update-service --cluster <c> --service <s> --task-definition <family:prev-rev>` | med | yes |

## Output

- Account/region confirmed, findings with commands used, proposed actions with risk/reversibility
