# Example 12: catching PHP2Shell across a small fleet, and the distro trap

**Skill:** [sre-php2shell-check](../../.claude/skills/sre-php2shell-check/SKILL.md), with `scripts/php2shell-check.sh`.

> **What's real here.** Command output comes from a lab run on 2026-10-23 with Python 3's built-in `http.server`. The lab stands in a local mock HTTP server instead of three real app servers so the walkthrough runs with no PHP installation and no network — the mock sends the same `X-Powered-By` header a real PHP app server would, and the skill's script has no idea it isn't talking to one. The report is **written in the skill's format** by the operator.

## What this shows

- Checking a small fleet in one run and reading the per-target status, not just the overall exit code.
- All three outcomes the skill can report for a version it actually found: `VULNERABLE`, `CHECK-DISTRO-PACKAGE` (an EOL branch with backport-only fixes), and `PATCHED`.
- Why `php -v` on a Debian/Ubuntu-style host can't be trusted on its own — a real, if synthetic, `dpkg` line that keeps the same upstream version string after a security backport.
- `--local` correctly reporting `UNKNOWN`, not a false "patched," on a host with no PHP installed at all — which is exactly what happened running this lab.

## Lab setup (no PHP installation needed)

[lab/php2shell/mock-server.py](lab/php2shell/mock-server.py) serves three paths, each with a different `X-Powered-By` header: `/checkout` (PHP/8.3.6, below the fix), `/admin` (PHP/8.1.31, an EOL branch), `/docs` (PHP/8.4.27, at the fixed build).

```console
$ REPO=$(git rev-parse --show-toplevel)
$ python3 "$REPO/docs/examples/lab/php2shell/mock-server.py" 19470 &
```

Then go to the skill, where the commands below run:

```console
$ cd "$REPO/.claude/skills/sre-php2shell-check"
```

## What broke

`checkout.shop.lab` is still on PHP 8.3.6, below the 8.3.36 build that fixes CVE-2026-109618/109619 — an unauthenticated RCE pair, CVSS 9.2, with exploitation attempts seen before the patch even shipped. `admin.shop.lab` is on PHP 8.1, which went end-of-life before this incident; whether it got a source-only backport is disputed in public reporting, so it needs a manual check against the vendor's own advisory rather than a clean read from the version number. `docs.shop.lab` is already on the fixed build.

## What you'd type

> Check checkout, admin and docs for the PHP2Shell CVEs.

## What the skill ran, and why

**1. Check all three in one run:**

```console
$ bash scripts/php2shell-check.sh --url http://127.0.0.1:19470/checkout --url http://127.0.0.1:19470/admin --url http://127.0.0.1:19470/docs; echo "exit=$?"
VULNERABLE http://127.0.0.1:19470/checkout 8.3.6 fixed-at-8.3.36
CHECK-DISTRO-PACKAGE http://127.0.0.1:19470/admin 8.1.31 eol-branch-source-backport-only-verify-vendor-advisory
PATCHED http://127.0.0.1:19470/docs 8.4.27 fixed-at-8.4.27
exit=1
```

Exit 1 means at least one source isn't a clean `PATCHED` — that covers both `checkout` (confirmed vulnerable) and `admin` (unresolved, not confirmed either way). Read every line; don't stop at the exit code once more than one target is involved.

**2. The distro trap, with a captured package query.** This lab host has no PHP installed at all, so `--local`'s own package-manager probe can't demonstrate the trap directly — instead, here's a real `dpkg -l 'php*'` line captured from a Debian/Ubuntu-style host, fed in the way this skill expects when you've gathered it separately (for example from an approved read elsewhere, like a Kubernetes `exec` done under `sre-k8s-triage`'s own gate, never by this skill execing in on its own):

```console
$ dpkg -l 'php*' | awk '/^ii/{print $2, $3}'
php8.3 8.3.6-1ubuntu3.2
```

The upstream version embedded in that string, `8.3.6`, is exactly what `php -v` would print before *and after* a security-only backport on this kind of distro package — the package revision (`-1ubuntu3.2`) and its changelog date are what actually tells you whether the Oct 21 fix is in, not the PHP version number. This skill's `--local` mode surfaces that package line as `CHECK-DISTRO-PACKAGE` specifically so it never gets read as a clean result:

```console
$ bash scripts/php2shell-check.sh --local; echo "exit=$?"
UNKNOWN local - php-not-on-PATH
exit=1
```

On this lab host, there's no `php` binary and no `php*` package at all, so `--local` correctly reports `UNKNOWN` rather than inventing a version — the same "don't guess" behavior that would fire a `CHECK-DISTRO-PACKAGE` line if `dpkg`/`rpm`/`apk` had found a package.

## The report (written in the skill's format)

```text
Scope checked: 3 lab endpoints (checkout, admin, docs on 127.0.0.1:19470) via X-Powered-By;
  1 captured dpkg line for the distro-trap illustration; --local on this host (no PHP present).

| status               | source    | version | detail                                              |
| VULNERABLE           | checkout  | 8.3.6   | fixed-at-8.3.36                                     |
| CHECK-DISTRO-PACKAGE | admin     | 8.1.31  | eol-branch-source-backport-only-verify-vendor-advisory |
| PATCHED              | docs      | 8.4.27  | fixed-at-8.4.27                                     |

Finding: checkout.shop.lab is confirmed below the fixed build -- internet-facing, no sign of
  pre-patch exploitation checked in this lab (would require log review, out of scope here).
Finding: admin.shop.lab is on an EOL branch with disputed backport coverage -- unresolved,
  not cleared, until checked against the vendor's own advisory.
Next step: checkout -> upgrade to >=8.3.36 via sre-change-safety (rollout plan, canary first).
  admin -> resolve the backport question before deciding whether it needs the same treatment.
No PHP version was changed, no server restarted, by this skill.
```

## The approval stop

This skill is read-only from start to finish. It never upgrades, restarts or patches PHP — the only real fix here is a version upgrade, and that's a production change. In a real incident, `checkout.shop.lab`'s owning team would take this finding to [sre-change-safety](../../.claude/skills/sre-change-safety/SKILL.md) for the upgrade (risk, reversibility, rollout plan); if log review turned up signs of pre-patch exploitation, it would go to [sre-security-incident-triage](../../.claude/skills/sre-security-incident-triage/SKILL.md) instead. Since this is a lab mock server and not a real production host, there's no approved action to show here.

## Cleanup

```console
$ kill %1   # stops the mock server
```

## What to take from this

- Read every line of a multi-target run. The exit code tells you "something needs attention," not which target or how badly.
- `CHECK-DISTRO-PACKAGE` and `UNKNOWN` are both "not cleared," not "probably fine" — this skill never reports them as `OK` by exit code or by status word, on purpose.
- `php -v` (or an `X-Powered-By` header built from the same version string) can look identical before and after a Debian/Ubuntu-style security backport. If PHP came from a distro package, the package's own changelog date is the thing to check against the advisory date, not the version number.
- An absent `X-Powered-By` header (most production configs disable it) proves nothing either way — this lab's mock sends it on purpose so the walkthrough has something to read; a real audit usually needs `--local` or a captured version string instead.
