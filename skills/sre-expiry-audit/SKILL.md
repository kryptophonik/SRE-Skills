---
name: sre-expiry-audit
description: "Use when asked what expires soon: TLS certs (endpoints, cert-manager), domain registrations, ACM/IAM certs, Secrets Manager rotation, GCP Secret/Certificate Manager, Azure Key Vault. Read-only metadata; flags 30/14/7 days."
---

# Expiry audit

## Safety gates (REQUIRED)

1. Read-only diagnosis first.
2. Propose each change with risk (low/med/high) and reversibility.
3. Wait for explicit human approval before any prod-changing command, MCP write tool, or external post.
4. Act only as approved, verify, and stop and escalate if anything gets worse.

Full rules: [sre-safety-gates](../sre-safety-gates/SKILL.md). Read-only MCP setup: [sre-safety-gates/references/mcp.md](../sre-safety-gates/references/mcp.md).

Cloud access: `sre-aws`, `sre-gcp`, `sre-azure` (read-only profiles). Kubernetes access: `sre-k8s-triage` rules.

## Rules

- **Metadata only.** Read names, dates, issuers and rotation settings. Never read a secret value: no `get-secret-value`, no `gcloud secrets versions access`, no `az keyvault secret show`, no `kubectl get secret -o yaml/json`. For a TLS secret, check the endpoint that serves it instead of decoding `tls.crt` (the same object holds `tls.key`).
- **Pin the target.** Every command names the account/profile and region, the project, the subscription, or the kube context. Run per region: ACM and Secrets Manager are regional (CloudFront certificates live in `us-east-1`).
- **Bounded.** `--limit`/`--max-items` on lists; sort by date; report only items inside the window, plus a count of the rest.
- **Renewal and rotation are out of scope.** Report the finding and the owner; the fix is a separate, gated change (see Proposals).

## Tiers

Default windows are **30 / 14 / 7 days** (override with the user's N). Every finding gets one tier:

| Tier | Days left | Meaning |
|---|---|---|
| EXPIRED | < 0 | already broken or about to be |
| 7d | 0–6 | page-worthy: renew today |
| 14d | 7–13 | renew this week |
| 30d | 14–29 | plan renewal |
| ok | ≥ 30 | count only |

Auto-renewing items (ACM `AMAZON_ISSUED` in use, cert-manager, Google-managed certs) are only a finding when they are inside a window, because that means renewal is failing. Report the renewal status next to them.

## Start here

1. Ask for scope: which endpoints, domains, clusters, accounts/projects/subscriptions, and N if not 30/14/7.
2. Endpoints and files (bundled, read-only TLS handshake only). The script has two thresholds (WARN/CRIT). Run it with `--warn 30 --crit 7` and put each line into a tier using its `DAYS_LEFT` column:

   ```bash
   bash scripts/cert-expiry.sh --warn 30 --crit 7 --timeout 10 <host>[:<port>] ... | awk '{d=$2; t=(d=="-")?"ERROR":(d<0)?"EXPIRED":(d<7)?"7d":(d<14)?"14d":(d<30)?"30d":"ok"; print t, $0}'
   bash scripts/cert-expiry.sh --warn 30 --crit 7 --file <cert.pem>
   ```

   Output: `STATUS DAYS_LEFT NOT_AFTER TARGET SUBJECT`; exit 0 all OK, 1 something inside a window, 2 usage or connection error. It checks the leaf only unless you add `--chain`, which also checks intermediates; see [references/tls.md](references/tls.md) for IPv6 (`[addr]:port`) and non-HTTPS ports.

3. Domains (bundled, RDAP):

   ```bash
   bash scripts/domain-expiry.sh --warn 30 --crit 7 <domain> ... | awk '{d=$2; t=(d=="-")?"CHECK":(d<0)?"EXPIRED":(d<7)?"7d":(d<14)?"14d":(d<30)?"30d":"ok"; print t, $0}'
   ```

   `NO-RDAP http-<status>` (lookup failed, or the TLD has no RDAP) and `UNKNOWN` (no expiration event) are not "ok": list them for a manual registrar or WHOIS check. Details: [references/domains.md](references/domains.md).

4. Kubernetes certificates (cert-manager and TLS secrets, metadata only): [references/kubernetes.md](references/kubernetes.md).
5. Cloud certificates and secrets (AWS ACM, IAM server certificates, Secrets Manager; GCP Certificate Manager, Compute SSL certificates, Secret Manager; Azure Key Vault): [references/cloud.md](references/cloud.md).
6. Merge everything into one table sorted by days left.

## Read these correctly

- `aws acm list-certificates` by default returns only RSA_1024/RSA_2048 certificates that have at least one domain, and leaves out ACME-origin certificates. Pass `--includes keyTypes=...` with every key type and `--certificate-key-pair-origins` to see everything ([references/cloud.md](references/cloud.md)). An audit without them misses every EC and RSA-3072/4096 certificate.
- GCP Secret Manager `expireTime` is the time Google **deletes the secret and every version, irreversibly**. It is not a rotation marker. Rotation is `rotation.nextRotationTime` (a Pub/Sub notification; your rotator does the work). A secret with `expireTime` inside the window is a data-loss finding, not a "rotate soon" finding.
- AWS Secrets Manager: `NextRotationDate` null means rotation is not configured or disabled. `LastRotatedDate` far behind the rotation schedule means rotation is failing.
- Azure Key Vault: `attributes.expires` (REST `exp`) is set by the owner and may be empty. Empty means "no expiry recorded", not "never expires" for a certificate: check the certificate's own date.

## Proposals (renewal, rotation)

This skill does not renew, rotate, re-import or change expiry dates. For each finding, give the owner, the item, the tier, and the path the owner uses. Typical paths: re-issue through cert-manager or the CA, re-import into ACM, rotate through the Secrets Manager rotation function, add a new Key Vault version, renew at the registrar. Each of those is a production change: run it through `sre-change-safety` with risk and reversibility.

**Gate: approval required.** Any renewal, rotation, expiry change or deletion. The approval names the exact item and the account/project/subscription/cluster. Removing or moving a GCP `expireTime` is also a change.

## Output

- Scope checked (targets, accounts/projects/subscriptions, clusters, regions) and anything that could not be checked, with the reason.
- One table: `tier | days left | expires (UTC) | item | where | owner | auto-renew / rotation status | next step`, sorted by days left, ok items as a count.
- Data-loss findings (GCP `expireTime`) called out separately.

## Bundled scripts and references

```bash
bash scripts/cert-expiry.sh [--warn 30] [--crit 7] [--timeout 10] [--chain] host[:port]|[ipv6]:port... | --file cert.pem...
bash scripts/domain-expiry.sh [--warn 30] [--crit 7] [--timeout 20] domain...
bash scripts/tests/run_tests.sh   # offline tests
```

- [references/tls.md](references/tls.md) · [references/domains.md](references/domains.md) · [references/kubernetes.md](references/kubernetes.md) · [references/cloud.md](references/cloud.md)

Last reviewed: 2026-10-17

## SOURCES

Fetched and checked 2026-10-17.

- `openssl s_client` (`-servername`, `-showcerts`: "as sent by the server ... not a verified chain"): https://docs.openssl.org/3.0/man1/openssl-s_client/ · `openssl x509` (`-enddate`, `-checkend`): https://docs.openssl.org/3.0/man1/openssl-x509/
- RDAP JSON responses, `eventAction: expiration`: https://www.rfc-editor.org/rfc/rfc9083.html · bootstrap redirector: https://rdap.org
- cert-manager `Certificate` status `notAfter`, `renewalTime`: https://cert-manager.io/docs/reference/api-docs/ · `renewBefore`/`duration`: https://cert-manager.io/docs/usage/certificate/
- `aws acm list-certificates` (`--includes keyTypes`, default RSA_1024/RSA_2048 with at least one domain; `--certificate-key-pair-origins`, ACME excluded by default; `NotAfter`, `InUse`, `RenewalEligibility`, `Type` in the summary): https://docs.aws.amazon.com/cli/latest/reference/acm/list-certificates.html · API filters: https://docs.aws.amazon.com/acm/latest/APIReference/API_ListCertificates.html · https://docs.aws.amazon.com/acm/latest/APIReference/API_Filters.html
- `aws acm describe-certificate` (`RenewalSummary.RenewalStatus`, AMAZON_ISSUED only): https://docs.aws.amazon.com/cli/latest/reference/acm/describe-certificate.html · managed renewal eligibility: https://docs.aws.amazon.com/acm/latest/userguide/managed-renewal.html
- CloudFront certificates in `us-east-1`: https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/cnames-and-https-requirements.html
- Route 53 domains `list-domains` (`Expiry`, `AutoRenew`): https://docs.aws.amazon.com/cli/latest/reference/route53domains/list-domains.html
- Kubernetes Secret `type` field selector: https://kubernetes.io/docs/concepts/overview/working-with-objects/field-selectors/ · `kubeadm certs check-expiration`: https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-certs/
- `aws iam list-server-certificates` (`Expiration`): https://docs.aws.amazon.com/cli/latest/reference/iam/list-server-certificates.html
- `aws secretsmanager describe-secret` (no secret value; `RotationEnabled`, `NextRotationDate`, `LastRotatedDate`): https://docs.aws.amazon.com/cli/latest/reference/secretsmanager/describe-secret.html · `list-secrets`: https://docs.aws.amazon.com/cli/latest/reference/secretsmanager/list-secrets.html
- GCP Secret Manager `expireTime` deletes the secret and all versions irreversibly; `rotation.nextRotationTime`: https://cloud.google.com/secret-manager/docs/reference/rest/v1/projects.secrets · https://cloud.google.com/secret-manager/docs/creating-and-managing-expiring-secrets · https://cloud.google.com/secret-manager/docs/secret-rotation · `gcloud secrets list`: https://cloud.google.com/sdk/gcloud/reference/secrets/list
- GCP Certificate Manager `expireTime`: https://cloud.google.com/certificate-manager/docs/reference/certificate-manager/rest/v1/projects.locations.certificates · `gcloud certificate-manager certificates list`: https://cloud.google.com/sdk/gcloud/reference/certificate-manager/certificates/list · Compute SSL certificate fields (`type`, `managed.status`, `expireTime`): https://cloud.google.com/compute/docs/reference/rest/v1/sslCertificates · `gcloud compute ssl-certificates list`: https://cloud.google.com/sdk/gcloud/reference/compute/ssl-certificates/list
- Azure Key Vault list returns identifiers and attributes only (`exp`): https://learn.microsoft.com/rest/api/keyvault/secrets/get-secrets/get-secrets · `az keyvault secret list`: https://learn.microsoft.com/cli/azure/keyvault/secret · `az keyvault certificate list`: https://learn.microsoft.com/cli/azure/keyvault/certificate · `az keyvault key list`: https://learn.microsoft.com/cli/azure/keyvault/key
