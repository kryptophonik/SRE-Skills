---
name: cloud-cost-review
description: "Cloud and observability cost review: idle and oversized resources, storage and snapshot sprawl, data transfer, commitments, and monitoring ingest/retention spend. Uses read-only AWS Cost Explorer, Azure Cost Management, GCP billing export, and Kubernetes requests vs. usage. Use for cost reviews or spend spikes; never deletes or resizes without approval."
---

# Cloud Cost Review

## Safety gates (REQUIRED)

Follow [sre-safety-gates](../sre-safety-gates/SKILL.md): read-only first; explicit approval before any prod change, MCP write, or external post. Deleting, stopping, or resizing anything is a prod change.

## Workflow

1. **Top spend:** by service, account/subscription/project, and tag for the last 30–90 days.
2. **Find waste (read-only):**
   - Idle: unattached volumes/disks, unused IPs, idle load balancers, stopped-but-billed resources.
   - Oversized: CPU < 20% p95 over 14 days; Kubernetes requests far above usage.
   - Storage: old snapshots, no lifecycle rules, hot tier for cold data.
   - Transfer: cross-AZ/region chatter, NAT gateway traffic.
   - Observability: high-cardinality metrics, debug logs in prod, long retention.
3. **Commitments:** Savings Plans/RIs/CUDs coverage vs. steady baseline.
4. **Rank** by monthly savings × confidence; note reliability risk (do not cut N+1 headroom).
5. **Propose** changes with owner; execute only after approval.

## Read-only commands

```bash
# AWS
# Cost Explorer: single endpoint us-east-1; billed per request (cache results); End is exclusive; paginated via NextPageToken
aws ce get-cost-and-usage --profile <profile> --region us-east-1 --time-period Start=<YYYY-MM-01>,End=<YYYY-MM-01> --granularity MONTHLY --metrics UnblendedCost --group-by Type=DIMENSION,Key=SERVICE
# Regional resources: repeat per region
aws ec2 describe-volumes --profile <profile> --region <region> --filters Name=status,Values=available --max-items 200
aws ec2 describe-addresses --profile <profile> --region <region> --query 'Addresses[?AssociationId==null]'
# Azure
# needs the costmanagement extension and Cost Management Reader
az costmanagement query --type ActualCost --timeframe Custom --time-period from=<YYYY-MM-DD> to=<YYYY-MM-DD> --scope /subscriptions/<subscription-id>
az disk list --subscription <subscription-id> --query "[?diskState=='Unattached']" -o table
# GCP
gcloud compute disks list --project=<PROJECT_ID> --filter="-users:*" --limit=100   # unattached disks
gcloud recommender recommendations list --project=<PROJECT_ID> --location=<ZONE> --recommender=google.compute.instance.MachineTypeRecommender
# Kubernetes requests vs usage
kubectl --context <ctx> -n <ns> top pods --sort-by=cpu | head -30
```

## Output

- Cost report: top spend, waste list with monthly savings estimate, reliability risk, owner, recommended action
