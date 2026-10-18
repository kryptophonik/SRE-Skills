# Domain registration expiry (RDAP)

Last reviewed: 2026-10-17. Sources: SOURCES in [../SKILL.md](../SKILL.md).

`bash scripts/domain-expiry.sh` asks `https://rdap.org` (or `RDAP_BASE`), which redirects to the registry's RDAP server. It reads the `expiration` event (RFC 9083 `eventAction: expiration`) and the registrar name.

- Its default thresholds are `--warn 45 --crit 14`. Pass `--warn 30 --crit 7` and use the tiers in SKILL.md.
- `NO-RDAP` ends with the HTTP status: `http-404` (not registered, or no RDAP for this TLD; several ccTLDs have none), `http-429` (rate limited: wait and retry fewer domains), `http-000` (no answer within `--timeout`, default 20 seconds). Check those domains at the registrar or with `whois <domain>`. WHOIS output formats differ by registry, so read the expiry line by eye.
- `UNKNOWN`: RDAP answered with no expiration event. Some registries do not publish one. Check at the registrar.
- The registry's date is the registration expiry. Registrar auto-renew may still be on. Report the auto-renew status from the registrar if you have access.
- Domains in a cloud registrar can be read from the cloud CLI as well, which is metadata only. For Route 53 domains, use `aws route53domains list-domains --profile <profile> --region us-east-1`, which includes `Expiry` and `AutoRenew`. Mark that as **docs-unverified** until it is checked live.

Sends: one HTTPS GET per domain to rdap.org and the registry. Nothing about your systems.
