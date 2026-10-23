---
name: sre-php2shell-check
description: "Use to check PHP hosts/containers for PHP2Shell (CVE-2026-109618, CVE-2026-109619), the Oct 2026 critical unauthenticated RCE pair, CVSS 9.2. Read-only version check (php -v, package manager, X-Powered-By); a hit needs a gated upgrade."
---

# PHP2Shell (CVE-2026-109618 / CVE-2026-109619) exposure check

## Safety gates (REQUIRED)

1. Read-only diagnosis first.
2. Propose each change with risk (low/med/high) and reversibility.
3. Wait for explicit human approval before any prod-changing command, MCP write tool, or external post.
4. Act only as approved, verify, and stop and escalate if anything gets worse.

Full rules: [sre-safety-gates](../sre-safety-gates/SKILL.md). This skill only reads a version string; it never upgrades, restarts or patches anything, and never execs into a container or remote host itself — see "Kubernetes and containers" below.

## Background

**PHP2Shell** is two critical, unauthenticated remote-code-execution flaws in core PHP: CVE-2026-109618 (use-after-free via out-of-memory request-setup corruption) and CVE-2026-109619 (use-after-free via request state that survives across a later request on the same worker). Both are CVSS 9.2 (watchTowr rated them 10.0). Disclosed and patched 2026-10-21; exploitation attempts were observed before the patch shipped. Every SAPI that serves web requests is exposed: PHP-FPM, Apache `mod_php`, `php-cgi`, FrankenPHP, LiteSpeed. `php` running only as a CLI script with no listener is not exposed to this.

**Fixed upstream builds:** PHP 8.2.35, 8.3.36, 8.4.27, 8.5.12. PHP 7.4, 8.0 and 8.1 are end-of-life; reports disagree on whether a source-only backport exists for them (no official binary release either way) — verify against your own vendor's advisory, don't assume either way. Anything on 7.3 or older has no modern vendor fix at all.

**The trap: `php -v` can lie to you.** On Debian/Ubuntu-style distros, a security backport is applied to the packaged source without bumping the upstream version string `php -v` prints — the host can be patched while `php -v` still reports the pre-patch version, or unpatched while looking identical to a patched one. Compare the **package's** version/changelog date against 2026-10-21, not the PHP version number, on any host where PHP came from a distro package rather than a source build or an upstream-published binary.

## Rules

- **Version only.** This skill reads `php -v` output, a package manager's installed-version query, or (best-effort, often absent) an `X-Powered-By` response header. It never execs code, never calls `phpinfo()` over the network, and never reads application files.
- **A missing `X-Powered-By` header proves nothing.** Most production configs disable it (`expose_php = Off`). Treat its absence as `UNKNOWN`, never as evidence of safety.
- **Distro-packaged PHP always needs a second check.** `CHECK-DISTRO-PACKAGE` is not a clean result — it means `php -v` can't be trusted on this host; the operator confirms the package's patch date, not its version string, against their distro's own advisory before closing the finding.
- **Kubernetes and containers:** never `kubectl exec` into a pod to run `php -v` from this skill directly — `exec` is a write under `sre-k8s-triage`'s rules and needs that skill's own approval path. Instead, check the **image tag/digest** against your build pipeline's PHP base-image version (read-only: `kubectl get pod <pod> -o jsonpath='{.spec.containers[*].image}'`, or your registry's own image metadata), or check the running service's `--url` endpoint if it's a web-facing one. If you must read the version from inside a running container, get that read approved as a `kubectl exec` under `sre-k8s-triage`/`sre-k8s-safe-remediation` first, capture the `php -v`/package-query text, then feed it to this skill with `--text`.
- **A finding is a finding, not a fix.** The only real remediation is upgrading PHP to a fixed build; there is no complete mitigation (not a WAF rule, not disabling a function) that the vendor considers sufficient on its own. Hand the upgrade to `sre-change-safety` (it's a runtime upgrade across every PHP worker — treat it like any other binary upgrade: canary where you can, roll out server-type by server-type, confirm app compatibility first on 8.2/8.3/8.4/8.5 if jumping a minor).

## Start here

1. Ask for scope: which hosts, containers/pods, and/or public endpoints to check, and whether PHP there is distro-packaged, built from source, or an upstream-published binary.
2. Run the checker against every target:

   ```bash
   bash scripts/php2shell-check.sh --local                      # this host: php -v + package manager
   bash scripts/php2shell-check.sh --url https://<host>/        # best-effort, remote, one HEAD request
   bash scripts/php2shell-check.sh --text <captured-php-v-or-package-query.txt>
   ```

   Output: `STATUS SOURCE VERSION DETAIL`. `STATUS` is `VULNERABLE`, `CHECK-DISTRO-PACKAGE`, `PATCHED`, `UNKNOWN` or `ERROR`. Exit 0 only if every source is `PATCHED`; exit 1 if any is `VULNERABLE`/`CHECK-DISTRO-PACKAGE`/`UNKNOWN` (none of those are clean); exit 2 on a usage/connection error. **The exit code is the worst single result** — read the per-line STATUS when checking more than one target.
3. For a fleet, repeat per host/pod/endpoint rather than guessing from one sample; PHP versions commonly drift across a fleet built at different times.
4. For every `VULNERABLE` or unresolved `CHECK-DISTRO-PACKAGE` finding, report it and stop. Hand off the upgrade to `sre-change-safety` with risk, reversibility, and a rollout plan; if the host was internet-facing and shows signs of pre-patch exploitation (unexpected worker crashes/restarts, OOM errors in logs around the request-handling path, unexplained new files or processes), treat it as a possible active compromise and route it to `sre-security-incident-triage` instead of a routine patch.

## Output

- Scope checked (hosts, pods/images, endpoints) and anything that couldn't be checked, with the reason.
- One table: `status | source | version found | detail`, `VULNERABLE` and `CHECK-DISTRO-PACKAGE` rows first.
- For each non-`PATCHED` finding: whether the host is internet-facing, and the hand-off (`sre-change-safety` for a routine upgrade, `sre-security-incident-triage` if pre-patch exploitation is suspected).

## Bundled scripts and references

```bash
bash scripts/php2shell-check.sh [--local] [--timeout 10] [--url <url> ...] [--text <file> ...]
bash scripts/tests/run_tests.sh   # offline tests
```

Last reviewed: 2026-10-23

## SOURCES

Fetched and checked 2026-10-23. Reporting on this incident is still developing; re-check php.net directly before relying on exact fixed-version numbers for a real decision.

- Bitsight, "CVE-2026-109618 and CVE-2026-109619 (PHP2Shell)": https://www.bitsight.com/blog/critical-vulnerability-alert-cve-2026-109618-and-cve-2026-109619-php2shell
- Kaspersky, PHP2Shell vulnerabilities: https://www.kaspersky.com/blog/cve-2026-109618-109619-php-vulnerabilities/56583/
- Help Net Security, "PHP2Shell: PHP vulnerabilities patched": https://www.helpnetsecurity.com/2026/10/21/php2shell-php-vulnerabilities-patched-cve-2026-109618-cve-2026-109619
- Huntress, "Rapid Response: php2shell": https://www.huntress.com/blog/php2shell-leaked-critical-php-vulnerabilities
- Canadian Centre for Cyber Security alert AL26-026: https://www.cyber.gc.ca/en/alerts-advisories/al26-026-critical-vulnerabilities-impacting-php-cve-2026-109618-cve-2026-109619
- PHP's own release notes and advisories (authoritative for fixed versions): https://www.php.net/
