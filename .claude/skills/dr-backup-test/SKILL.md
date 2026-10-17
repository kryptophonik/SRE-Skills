---
name: dr-backup-test
description: "Plans and runs backup-restore and disaster-recovery drills against RTO/RPO targets: restore to an isolated target, failover game days, evidence record. Uses cloud CLIs (aws backup/rds, az backup, gcloud sql) and Velero for Kubernetes, restoring only to new isolated targets after approval. Use when testing backups or DR readiness."
---

# Backup and DR Testing

## Safety gates (REQUIRED)

Follow [sre-safety-gates](../sre-safety-gates/SKILL.md): read-only first; explicit approval before any prod change, MCP write, or external post.

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
aws backup list-backup-jobs --by-state COMPLETED --max-results 20
aws rds describe-db-snapshots --db-instance-identifier <db>
# Azure
az backup job list --resource-group <rg> --vault-name <vault> --subscription <subscription-id> --status Completed --start-date <dd-mm-yyyy> -o table
# GCP
gcloud sql backups list --instance=<instance>
# Kubernetes (Velero)
velero backup get
velero backup describe <backup> --details
```

## Restore commands (WRITE — approval required, new target only)

```bash
aws rds restore-db-instance-from-db-snapshot --db-instance-identifier <new-db> --db-snapshot-identifier <snap>
aws rds restore-db-instance-to-point-in-time --source-db-instance-identifier <db> --target-db-instance-identifier <new-db> --restore-time <ISO8601>
velero restore create --from-backup <backup> --namespace-mappings <ns>:<ns>-drtest
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
