# Kubernetes certificates (metadata only)

Last reviewed: 2026-10-17. Sources: SOURCES in [../SKILL.md](../SKILL.md). Same rules as `sre-k8s-triage`: every command carries `--context <ctx>`. Never read Secret data.

## cert-manager

`Certificate` status carries `notAfter` (expiry of the cert in `spec.secretName`) and `renewalTime` (next scheduled renewal; empty means none scheduled):

```bash
kubectl --context <ctx> get certificates -A -o custom-columns='NS:.metadata.namespace,NAME:.metadata.name,READY:.status.conditions[?(@.type=="Ready")].status,NOT_AFTER:.status.notAfter,RENEWAL:.status.renewalTime,SECRET:.spec.secretName,ISSUER:.spec.issuerRef.name' --sort-by=.status.notAfter | head -n 100
kubectl --context <ctx> get certificaterequests -A --sort-by=.metadata.creationTimestamp | tail -n 20
```

Findings:
- `notAfter` inside a window with `renewalTime` in the past, or `READY=False`: renewal is failing. Check the Certificate's events and the issuer, read-only: `kubectl --context <ctx> -n <ns> describe certificate <name>` and `kubectl --context <ctx> -n <ns> events --for certificate/<name> | tail -n 50`. Typical causes are ACME challenge failures, an issuer that is not Ready, or rate limits.
- `renewalTime` empty on a Ready certificate: nothing will renew it.
- `renewBefore` and `duration` use Go duration strings (`h`, not `d`).

## TLS Secrets not managed by cert-manager

List them by type and metadata only, then check the endpoint that serves each one with `bash scripts/cert-expiry.sh` (see SKILL.md):

```bash
kubectl --context <ctx> get secrets -A --field-selector type=kubernetes.io/tls -o custom-columns='NS:.metadata.namespace,NAME:.metadata.name,CERT_MANAGER:.metadata.annotations.cert-manager\.io/certificate-name,CREATED:.metadata.creationTimestamp' | head -n 200
kubectl --context <ctx> get ingress -A -o custom-columns='NS:.metadata.namespace,NAME:.metadata.name,HOSTS:.spec.rules[*].host,TLS_SECRET:.spec.tls[*].secretName' | head -n 200
```

Never `-o yaml`/`-o json` on a Secret, and never `jsonpath='{.data...}'`. The object holds `tls.key`. If a certificate is not reachable from where you run, such as an internal-only service or mTLS between workloads, the owner checks it on their side. Report it as "not checked".

## Webhook and API server certificates

- Admission webhooks: `kubectl --context <ctx> get validatingwebhookconfigurations,mutatingwebhookconfigurations` lists them. Their CA bundles are often injected by cert-manager's cainjector, so the cert-manager list above covers them.
- Control-plane certificates are managed by the provider on managed clusters (EKS/GKE/AKS). On kubeadm clusters, the owner runs `kubeadm certs check-expiration` on a control-plane node. That is read-only, but it needs node access, so list it as a step for the owner.
