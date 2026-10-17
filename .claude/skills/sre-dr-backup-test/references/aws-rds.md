# AWS RDS restore drill (reference for sre-dr-backup-test)

Verified 2026-10-16 against AWS CLI 2.38.1:
https://awscli.amazonaws.com/v2/documentation/api/latest/reference/rds/restore-db-instance-from-db-snapshot.html
https://awscli.amazonaws.com/v2/documentation/api/latest/reference/rds/restore-db-instance-to-point-in-time.html
https://awscli.amazonaws.com/v2/documentation/api/latest/reference/rds/delete-db-instance.html
Follow [sre-safety-gates](../../sre-safety-gates/SKILL.md).

## Why explicit isolation is needed
If you don't override them, a restore inherits the default security group and default DB parameter group, and uses Single-AZ. It is not isolated by default. MySQL and PostgreSQL also default to `open-source-rds-extended-support`, which can add charges. Aurora uses `restore-db-cluster-from-snapshot` and needs a separate `create-db-instance`; it is not covered here.

## 1. Inventory (read-only)
```bash
aws rds describe-db-snapshots --db-instance-identifier <db> --snapshot-type automated --max-items 20 --profile <profile> --region <region>
aws rds describe-db-instances --db-instance-identifier <db> --query 'DBInstances[0].[LatestRestorableTime,DBInstanceClass,Engine,EngineVersion]' --profile <profile> --region <region>
aws rds describe-db-subnet-groups --db-subnet-group-name <isolated-subnet-group> --profile <profile> --region <region>
```
Prerequisites: an isolated DB subnet group (no route to production, no internet gateway) and a security group that only allows the drill runner.

## 2. Restore (WRITE: creates a billable resource, approval required)
Name restored instances `drtest-<db>-<yyyymmdd>`. Cleanup refuses any other prefix.
```bash
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier drtest-<db>-<yyyymmdd> \
  --db-snapshot-identifier <snapshot-id-or-shared-arn> \
  --db-subnet-group-name <isolated-subnet-group> \
  --vpc-security-group-ids <isolated-sg-id> \
  --no-publicly-accessible --no-multi-az \
  --db-instance-class <small-class> \
  --no-deletion-protection --backup-retention-period 0 \
  --tags Key=purpose,Value=dr-drill Key=expires,Value=<yyyy-mm-dd> \
  --profile <profile> --region <region>

# or point-in-time (records real RPO; --use-latest-restorable-time instead of --restore-time):
aws rds restore-db-instance-to-point-in-time \
  --source-db-instance-identifier <db> \
  --target-db-instance-identifier drtest-<db>-<yyyymmdd> \
  --restore-time <ISO8601-UTC> \
  --db-subnet-group-name <isolated-subnet-group> --vpc-security-group-ids <isolated-sg-id> \
  --no-publicly-accessible --no-multi-az --db-instance-class <small-class> \
  --tags Key=purpose,Value=dr-drill Key=expires,Value=<yyyy-mm-dd> \
  --profile <profile> --region <region>
aws rds wait db-instance-available --db-instance-identifier drtest-<db>-<yyyymmdd> --profile <profile> --region <region>
```
Record the start time and the time it became available. That gap is the RTO.

## 3. Validate (read-only against the drill instance)
Compare row counts and checksums against the source. The newest record timestamp tells you the actual RPO. Connect with drill credentials only, never production application credentials.

## 4. Cleanup (WRITE: irreversible, separate approval required)
```bash
id=drtest-<db>-<yyyymmdd>
[[ "$id" == drtest-* ]] || { echo "refusing: not a drill instance"; exit 1; }
aws rds describe-db-instances --db-instance-identifier "$id" \
  --query 'DBInstances[0].TagList[?Key==`purpose`].Value' --output text --profile <profile> --region <region>  # must print dr-drill
aws rds delete-db-instance --db-instance-identifier "$id" --skip-final-snapshot --delete-automated-backups \
  --profile <profile> --region <region>
```
Never run the cleanup against an identifier without the `drtest-` prefix and the `purpose=dr-drill` tag.

## Output
Snapshot used, target RTO/RPO and achieved RTO/RPO, validation results, cost window (create to delete time), gaps to file as tickets.
