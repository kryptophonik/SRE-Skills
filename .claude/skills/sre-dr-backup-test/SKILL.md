---
name: sre-dr-backup-test
description: "Use when testing backups or DR readiness: backup-restore and failover drills against RTO/RPO, restoring only to new isolated targets after approval, with an evidence record."
---

# Backup and DR Testing

## Safety gates (REQUIRED)

1. Read-only diagnosis first.
2. Propose each change with risk (low/med/high) and reversibility.
3. Wait for explicit human approval before any prod-changing command, MCP write tool, or external post.
4. Act only as approved, verify, and stop and escalate if anything gets worse.

Full rules: [sre-safety-gates](../sre-safety-gates/SKILL.md). Read-only MCP setup: [sre-safety-gates/references/mcp.md](../sre-safety-gates/references/mcp.md).

Never restore over a live resource. Always restore to a **new, isolated** target (new resource group / account / project, isolated network). On Azure, restore `--target-resource-group` must be a new drill RG; ASR uses **test failover** into an isolated VNet only.

## No-go rules

- No written RTO/RPO target for the system.
- Restore target is not isolated (could receive prod traffic or overwrite prod data).
- No owner or timebox; no approval.
- Active incident on the system.

## Workflow

1. **Scope:** system, data stores, RTO (time to restore) and RPO (acceptable data loss).
2. **Inventory backups (read-only):** schedule, retention, last success, encryption, cross-region/account copy.
3. **Plan the drill:** restore type (single table/file, full DB, cluster, region failover), target, validation queries, timebox, rollback/cleanup.
4. **Get approval.**
5. **Run:** start timer; restore to isolated target.
6. **Validate:** row counts / checksums vs. source, app smoke test, newest record timestamp (gives real RPO).
7. **Record** achieved RTO/RPO vs. target; gaps become tickets.
8. **Clean up** restored resources (after approval) to avoid cost and data exposure.

## Read-only inventory commands

```bash
# AWS
aws backup list-backup-jobs --profile <profile> --region <region> --by-state COMPLETED --by-created-after <ISO8601> --max-items 20
aws rds describe-db-snapshots --profile <profile> --region <region> --db-instance-identifier <db> --snapshot-type automated --max-items 20
# Azure
az backup job list --resource-group <rg> --vault-name <vault> --subscription <subscription-id> --status Completed --start-date <dd-mm-yyyy> -o table
# GCP
gcloud sql backups list --instance=<instance> --project=<PROJECT_ID> --limit=20
# Kubernetes (Velero)
velero backup get | head -30
velero backup describe <backup> --details
```

## Restore commands (WRITE — approval required, new target only)

Full AWS RDS drill (inventory, isolated restore, validation, RTO/RPO, tag-checked cleanup): [references/aws-rds.md](references/aws-rds.md).

```bash
# RDS restores are billable and NOT isolated by default (default SG, default subnet group). Always override:
aws rds restore-db-instance-from-db-snapshot --profile <profile> --region <region> --db-instance-identifier drtest-<db>-<date> --db-snapshot-identifier <snap> \
  --db-subnet-group-name <isolated-subnet-group> --vpc-security-group-ids <isolated-sg> --no-publicly-accessible --no-multi-az \
  --db-instance-class <small-class> --tags Key=purpose,Value=dr-drill
# MySQL/PostgreSQL restores may default to RDS Extended Support (extra charges); set --engine-lifecycle-support if needed
aws rds restore-db-instance-to-point-in-time --profile <profile> --region <region> --source-db-instance-identifier <db> --target-db-instance-identifier drtest-<db>-<date> \
  --restore-time <ISO8601> --db-subnet-group-name <isolated-subnet-group> --vpc-security-group-ids <isolated-sg> --no-publicly-accessible --no-multi-az \
  --db-instance-class <small-class> --tags Key=purpose,Value=dr-drill      # or --use-latest-restorable-time instead of --restore-time
# Aurora: restore a cluster, then add an instance
aws rds restore-db-cluster-from-snapshot --profile <profile> --region <region> --db-cluster-identifier drtest-<cluster>-<date> --snapshot-identifier <snap> --engine <aurora-mysql|aurora-postgresql> \
  --db-subnet-group-name <isolated-subnet-group> --vpc-security-group-ids <isolated-sg> --tags Key=purpose,Value=dr-drill
# Cleanup (WRITE, approval required): only if the identifier starts with drtest-
aws rds delete-db-instance --profile <profile> --region <region> --db-instance-identifier drtest-<db>-<date> --skip-final-snapshot
velero restore create --from-backup <backup> --namespace-mappings <ns>:<ns>-drtest
# GCP Cloud SQL: restore to a NEW isolated instance, never the source instance (Google: "The restore process overwrites all of the current data on the instance, including previous point-in-time recovery (PITR) logs." — https://cloud.google.com/sql/docs/mysql/backup-recovery/restoring)
gcloud sql backups restore <BACKUP_ID> --restore-instance=<NEW_ISOLATED_INSTANCE> --backup-instance=<SOURCE_INSTANCE> --project=<PROJECT_ID>
# Azure VM: restore disks to a NEW resource group / storage account, never the original location
az backup restore restore-disks --resource-group <vault-rg> --vault-name <vault> --container-name <container> --item-name <vm> --rp-name <recovery-point> --storage-account <new-staging-sa> --target-resource-group <new-drtest-rg> --subscription <subscription-id>
# Azure SQL / SAP HANA workloads in VMs: restore as a new database to an alternate target
az backup restore restore-azurewl --resource-group <vault-rg> --vault-name <vault> --recovery-config <recovery-config.json> --subscription <subscription-id>
# Azure Site Recovery: run a TEST failover into an isolated network (not a planned/unplanned failover)
az site-recovery protected-item test-failover --resource-group <rg> --vault-name <asr-vault> --fabric-name <fabric> --protection-container <container> --name <protected-item> --subscription <subscription-id> # params vary by version; check `az site-recovery protected-item test-failover -h`
```

## Drill record template

```markdown
# DR drill: [system] — [date]
- **Scenario:** [restore / failover]
- **Targets:** RTO [x] / RPO [y]
- **Achieved:** RTO [x'] / RPO [y'] — [pass|fail]
- **Validation:** [checks + results]
- **Issues found:** [list → tickets]
- **Cleanup done:** [yes/no, by whom]
- **Approved by:** [name, time]
```

## Output

- Drill record with achieved vs. target RTO/RPO, validation evidence, gaps as tickets
