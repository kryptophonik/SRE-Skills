# Cloud certificate and secret expiry (metadata only)

Last reviewed: 2026-10-17. Sources: SOURCES in [../SKILL.md](../SKILL.md). Use the read-only identities from `sre-aws`, `sre-gcp` and `sre-azure`. None of these commands returns a secret value.

## AWS

ACM is regional. Run it in every region you use, plus `us-east-1` for CloudFront.

By default, `list-certificates` returns only RSA_1024/RSA_2048 certificates that have at least one domain, and skips ACME-origin certificates. Ask for every key type and origin:

```bash
aws acm list-certificates --profile <profile> --region <region> \
  --includes keyTypes=RSA_1024,RSA_2048,RSA_3072,RSA_4096,EC_prime256v1,EC_secp384r1,EC_secp521r1 \
  --certificate-key-pair-origins AWS_MANAGED CUSTOMER_PROVIDED ACME \
  --query 'sort_by(CertificateSummaryList, &to_string(NotAfter))[].[NotAfter, DomainName, Status, Type, InUse, RenewalEligibility, CertificateArn]' --output table
```

- An older AWS CLI may reject `--certificate-key-pair-origins`. Drop it, and note that ACME certificates were not listed.
- `Type = IMPORTED`: ACM never renews it, so the owner must re-import.
- `Type = AMAZON_ISSUED` inside a window: renewal is failing. Find out why:

```bash
aws acm describe-certificate --profile <profile> --region <region> --certificate-arn <arn> --query 'Certificate.{NotAfter:NotAfter,Renewal:RenewalSummary.RenewalStatus,Reason:RenewalSummary.RenewalStatusReason,InUseBy:InUseBy}'
```

IAM server certificates (older ELB/CloudFront setups) are global:

```bash
aws iam list-server-certificates --profile <profile> --query 'sort_by(ServerCertificateMetadataList, &to_string(Expiration))[].[Expiration, ServerCertificateName, Arn]' --output table
```

Secrets Manager rotation metadata (`describe-secret` and `list-secrets` do not return the value):

```bash
aws secretsmanager list-secrets --profile <profile> --region <region> --max-items 200 --query 'SecretList[].[Name, RotationEnabled, LastRotatedDate, NextRotationDate, LastAccessedDate]' --output table
aws secretsmanager describe-secret --profile <profile> --region <region> --secret-id <name-or-arn> --query '{Rotation:RotationEnabled,Rules:RotationRules,Last:LastRotatedDate,Next:NextRotationDate}'
```

- `NextRotationDate` null means rotation is not configured or disabled. Report it only if the owner expects rotation.
- `NextRotationDate` in the past, or `LastRotatedDate` older than the schedule, means rotation is failing.
- Never `get-secret-value`.

## GCP

Certificate Manager and the Compute SSL certificates are separate stores. Check both.

```bash
gcloud certificate-manager certificates list --project=<PROJECT_ID> --location=<REGION|global> --sort-by=expireTime --limit=200 --format='table(name.basename(), expireTime, managed.state, sanDnsnames.list())'
gcloud compute ssl-certificates list --project=<PROJECT_ID> --sort-by=expireTime --limit=200 --format='table(name, type, expireTime, managed.status)'
```

Secret Manager:

```bash
gcloud secrets list --project=<PROJECT_ID> --limit=200 --format='table(name.basename(), expireTime, rotation.nextRotationTime, rotation.rotationPeriod)'
```

- **`expireTime` is deletion.** At that time Google deletes the secret and all its versions, irreversibly. Flag any `expireTime` inside the window as a **data-loss** finding, with the owner. Moving or removing it is a gated change.
- **Rotation is `rotation.nextRotationTime`.** It only sends a `SECRET_ROTATE` Pub/Sub message to the secret's topics; something the owner runs does the actual rotation. A `nextRotationTime` in the past usually means the rotator is not working.
- Never `gcloud secrets versions access`.

## Azure Key Vault

List calls return identifiers and attributes only; the REST field `exp` shows as `attributes.expires`. They need the list permission on the vault, not get.

```bash
az keyvault certificate list --subscription <subscription-id> --vault-name <vault> --maxresults 200 --query "sort_by([?attributes.expires!=null], &attributes.expires)[].{name:name, expires:attributes.expires, enabled:attributes.enabled}" -o table
az keyvault secret list --subscription <subscription-id> --vault-name <vault> --maxresults 200 --query "sort_by([?attributes.expires!=null], &attributes.expires)[].{name:name, expires:attributes.expires, enabled:attributes.enabled, contentType:contentType}" -o table
az keyvault key list --subscription <subscription-id> --vault-name <vault> --maxresults 200 --query "sort_by([?attributes.expires!=null], &attributes.expires)[].{name:name, expires:attributes.expires, enabled:attributes.enabled}" -o table
```

- `expires` is optional. A secret without it has no expiry recorded; count those separately.
- A certificate always has its own end date in the certificate itself. If `expires` is empty there, check the endpoint that uses it with `bash scripts/cert-expiry.sh`.
- Never `az keyvault secret show` or `az keyvault secret download`. Both return the value.
- Key Vault-managed certificate renewal, and key rotation policies, are owner changes (gated).
