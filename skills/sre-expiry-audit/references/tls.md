# TLS endpoints and certificate files

Last reviewed: 2026-10-17. Sources: SOURCES in [../SKILL.md](../SKILL.md).

`bash scripts/cert-expiry.sh` does one TLS handshake per target with SNI (`-servername`) and reads the leaf certificate's `notAfter` (all certificates with `--chain`). It sends no application data.

## Limits of the bundled check

- **Leaf only by default.** An expiring intermediate breaks clients just as hard. Add `--chain` to check every certificate the server sends, or every certificate in a `--file` bundle; extra ones print as `TARGET#2`, `TARGET#3`. `openssl s_client -showcerts` gives the certificates "as sent by the server ... not a verified chain", so `--chain` reports dates, not trust.
- **IPv6 literals** need brackets: `[2001:db8::1]:443`. A bare `2001:db8::1` prints `ipv6-needs-brackets`. IP literals get no SNI, so a shared front end may return its default certificate; prefer the DNS name.
- **STARTTLS services** (SMTP, IMAP, Postgres, LDAP) need `openssl s_client -starttls <proto>`. The script does not do that. Check those by hand, or check the certificate file or secret on the server side.
- **Load balancers with several nodes or regions** may serve different certificates. Check each regional endpoint or the certificate store behind it (ACM, Certificate Manager, Key Vault: see [cloud.md](cloud.md)).
- `-checkend <seconds>` is a quick yes/no test for one file: `openssl x509 -in <cert.pem> -noout -checkend 2592000` (30 days; exit 1 means it expires inside the window).

## What not to do

- Do not point the script at a private key, a PKCS#12 bundle, or a Kubernetes secret dump. Certificate files only.
- Do not fix a WARN by restarting anything or editing an ingress. Renewal is a proposal (SKILL.md, Proposals).
