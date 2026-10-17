# Read-only IAM for the aws skill

Verified 2026-10-16 against:
- ViewOnlyAccess v47, edited 2026-10-14: https://docs.aws.amazon.com/aws-managed-policy/latest/reference/ViewOnlyAccess.html
- aws-api-mcp-server README (main): https://github.com/awslabs/mcp/tree/main/src/aws-api-mcp-server
- Cost Explorer API: https://docs.aws.amazon.com/cost-management/latest/userguide/ce-api.html

## Which base policy
- **ViewOnlyAccess (recommended base).** It covers metadata only: `cloudwatch:Get*`/`List*`, `logs:Describe*`, `rds:Describe*`, `ec2:Describe*` (subset), `autoscaling:Describe*`, `elasticloadbalancing:DescribeTargetHealth`, `eks:DescribeCluster`, `backup:List*`, `cloudtrail:LookupEvents`. As of v47 it does NOT include `ce:*`, `health:*`, `logs:StartQuery`, `logs:GetQueryResults`, `logs:FilterLogEvents` or `sts`. `readonly-iam-policy.json` adds those.
- **ReadOnlyAccess.** Broader, and it can read data (S3 objects, log events, some secret material). If you use it, attach the Deny statement from the JSON. The awslabs README warns that read-only operations "can still return AWS credentials or sensitive information".
- The Deny statements override any Allow. Note that `kms:Decrypt` denial also blocks reading encrypted log groups and SSM SecureString parameters through the console. That's intended.
- Cost note: `ce:*` and `logs:StartQuery` are charged per request or per GB scanned. Grant them only to roles that need them. See cost-and-limits.md.
- Health organizational view (`health:DescribeEventsForOrganization` and related) is not included. Use it only from the management account or a delegated administrator. See cost-and-limits.md.
