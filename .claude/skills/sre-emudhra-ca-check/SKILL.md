---
name: sre-emudhra-ca-check
description: "Use to check whether a TLS/code-signing cert chains through one of the 8 eMudhra intermediate CAs revoked for private-key compromise, Oct 2026 (Mozilla bug 2083449): endpoints, cert files, k8s TLS secrets. Read-only; a match needs a gated reissue."
---

# eMudhra intermediate CA compromise check

## Safety gates (REQUIRED)

1. Read-only diagnosis first.
2. Propose each change with risk (low/med/high) and reversibility.
3. Wait for explicit human approval before any prod-changing command, MCP write tool, or external post.
4. Act only as approved, verify, and stop and escalate if anything gets worse.

Full rules: [sre-safety-gates](../sre-safety-gates/SKILL.md). This skill only reads certificates; it never issues, revokes or deploys one.

## Background

In October 2026, eight eMudhra intermediate CAs (six TLS, two code-signing) turned out to have private keys weak enough to reconstruct from the public certificate — a key-generation script bug, not a theft. Google, Mozilla, Apple and Microsoft revoked trust in the affected intermediates and in `emSign ECC Root CA - G3`; Sectigo revoked its cross-signs of the same intermediates. eMudhra says its root keys and most production issuance were unaffected, but any certificate that does chain through one of the eight is signed by a key anyone could have derived, independent of whether it was ever misused.

**Why this isn't covered by browser trust alone:** Chrome, Firefox, Safari and Edge block these intermediates for people browsing to you in those browsers. They do nothing for your own service-to-service TLS, internal CAs, mobile apps with certificate pinning, CI/CD code-signing, or any client with its own trust store (curl, custom gRPC stacks, IoT, most non-browser software). This skill finds every certificate on your inventory that chains through the compromised intermediates so you can reissue it, regardless of what a browser would show a visitor.

**This list goes stale.** The bundled [references/compromised-intermediates.json](references/compromised-intermediates.json) is a point-in-time snapshot (captured 2026-10-23) from Mozilla Bugzilla bug 2083449 and eMudhra's own advisory. Before relying on a clean result for a real decision, cross-check against [CCADB](https://www.ccadb.org/) and Mozilla's OneCRL, since the set of revoked serials can grow as cross-signs and backdated issuances are found.

## Rules

- **Check the whole chain, not just the leaf.** The compromise is at the intermediate. A server can present a perfectly fine leaf signed by a compromised intermediate; `openssl s_client -showcerts` is used unconditionally, never leaf-only.
- **Metadata only.** Serial number and SHA-256 fingerprint of each certificate in the chain. Never read a private key, and for a Kubernetes `kubernetes.io/tls` Secret, check the serving endpoint instead of decoding `tls.crt` out of the Secret (the same object holds `tls.key`).
- **Bounded.** Pass an explicit, finite list of targets (hosts, files, namespaces). No unbounded crawl of a CT log or the whole internet.
- **A match is a finding, not an incident fix.** Reissuing the certificate from a different, unaffected CA (or a non-compromised eMudhra intermediate after eMudhra's remediation) is a production change: hand it to `sre-change-safety`, and if the certificate was actually relied on for authentication (mTLS, code-signing trust, not just serving TLS to the public internet), to `sre-security-incident-triage` as well.

## Start here

1. Ask for scope: which endpoints (host:port), certificate files/bundles, and/or Kubernetes contexts and namespaces to check. For Kubernetes, enumerate `kubernetes.io/tls` Secrets' endpoints with `sre-k8s-triage`'s read-only commands first, then check those endpoints here — don't decode the Secret.
2. Run the checker against every target:

   ```bash
   bash scripts/emudhra-ca-check.sh --timeout 10 <host>[:<port>] ...
   bash scripts/emudhra-ca-check.sh --file <cert-or-bundle.pem> ...
   ```

   Output: `STATUS TARGET POSITION SUBJECT SHA256`, one line per certificate in the chain (`1(leaf)`, `2`, `3`, ...). `STATUS` is `COMPROMISED`, `OK` or `ERROR`. Exit 0 if every certificate on every target is OK, 1 if any is `COMPROMISED`, 2 on a usage or connection error — **the exit code is the worst single result, so always read the per-line STATUS when checking more than one target**, the same convention as `sre-expiry-audit`'s `cert-expiry.sh`.
3. For code-signing trust (not a TLS endpoint): extract the signer's certificate chain from the signed artifact (e.g. `osslsigncode extract-signature`, `jarsigner -verify -verbose -certs`, or your platform's equivalent) to a PEM file and run the same `--file` check against it.
4. For every `COMPROMISED` finding, report it and stop — do not reissue, revoke or redeploy anything from this skill. Hand off:
   - **Reissue:** the owning team requests a new certificate from a CA not on the affected list, through `sre-change-safety` (risk, reversibility, rollout plan — a TLS cert swap is usually low risk if paired with a monitoring check, but an mTLS client cert swap can break every caller at once, so verify no-downtime rollout first).
   - **If the certificate authenticated something** (mTLS between services, a code-signing trust anchor, an internal CA cross-sign) rather than just serving a public web page: treat it as a possible compromise of that trust relationship, not just an expiring-style housekeeping item, and loop in `sre-security-incident-triage`.

## Reading the result

- `COMPROMISED` on position `1(leaf)` means the leaf certificate itself was issued by (or in rare cases, is itself one of) a revoked intermediate — the certificate in active use is signed with a reconstructable key.
- `COMPROMISED` on a later position means an intermediate further up the chain is affected, even if the leaf itself looks fine; the leaf still needs to be reissued under a clean chain.
- `ERROR` on a target means the check didn't run (connection failed, file unreadable, certificate unparseable) — it is not a clean result. Re-run it; don't report it as OK.
- A target with no match against this skill's bundled list but a chain to `AAA Certificate Services`, `emSign Root TLS CA - G3`, `emSign Root CS CA - G3` or `emSign ECC Root CA - G3` (the affected root hierarchies) is not itself compromised, but is worth a second look against CCADB/OneCRL directly, since the bundled list may not be current.

## Output

- Scope checked (targets, files, namespaces) and anything that could not be checked, with the reason.
- One table: `status | target | position in chain | subject | sha256`, `COMPROMISED` rows first.
- For each `COMPROMISED` finding: whether it authenticates something beyond public-web TLS, and the hand-off (`sre-change-safety` for reissue, plus `sre-security-incident-triage` if it authenticated a trust relationship).

## Bundled scripts and references

```bash
bash scripts/emudhra-ca-check.sh [--timeout 10] [--data compromised-intermediates.json] [host[:port]|[ipv6]:port...] [--file cert.pem [cert.pem...]]
bash scripts/tests/run_tests.sh   # offline tests
```

- [references/compromised-intermediates.json](references/compromised-intermediates.json) — the 8 eMudhra-issued + 8 Sectigo cross-signed revoked intermediates (serials, SHA-256 fingerprints, issuing root). Verify against CCADB/OneCRL before relying on it; update this file, not the script, when the authoritative list changes.

Last reviewed: 2026-10-23

## SOURCES

Fetched and checked 2026-10-23.

- Mozilla Bugzilla bug 2083449 (eMudhra intermediate CA private-key compromise, revoked intermediates, serials and SHA-256 fingerprints): https://bugzilla.mozilla.org/show_bug.cgi?id=2083449
- eMudhra's own incident statement: https://emudhra.com/en/post/certificate-security-incident
- CCADB, the canonical cross-vendor registry of CA certificates and their status: https://www.ccadb.org/
- `openssl x509` (`-serial`, `-fingerprint -sha256`): https://docs.openssl.org/3.0/man1/openssl-x509/ · `openssl s_client` (`-showcerts`): https://docs.openssl.org/3.0/man1/openssl-s_client/
