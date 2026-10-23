# Example 11: finding a certificate behind a compromised eMudhra intermediate

**Skill:** [sre-emudhra-ca-check](../../.claude/skills/sre-emudhra-ca-check/SKILL.md), with `scripts/emudhra-ca-check.sh`.

> **What's real here.** Command output comes from a lab run on 2026-10-23 with OpenSSL 3.5.7 and Python 3. The lab never touches a real compromised eMudhra certificate (that would need the compromised CA's private key, which nobody should have): instead it writes a synthetic data file containing one lab cert's own serial and SHA-256 fingerprint, labeled as if it came from the revoked `EM DV TLS CA - G3B` intermediate, so the real checker script has something genuine to match. The report is **written in the skill's format** by the operator.

## What this shows

- Checking every certificate in a chain, not just the leaf — the compromise this skill looks for is in an intermediate.
- A synthetic "this cert is compromised" fixture, built from the lab cert's own fingerprint, so the match logic is exercised against real openssl/python output, not a mocked function.
- The same two lab certs checked against the real bundled `compromised-intermediates.json` and correctly coming back clean, since neither is an actual eMudhra certificate.
- `--file` working the same way as a live endpoint, for certs sitting in a repo before they're deployed.

## Lab setup (OpenSSL only)

[lab/emudhra-ca-check/mk-fixture.sh](lab/emudhra-ca-check/mk-fixture.sh) makes two self-signed leaf certs — `payments-api` and `docs-site` — and a `compromised-fixture.json` built from `payments-api`'s own serial and fingerprint. Run it in a temporary directory (`$LAB`, used again below), then serve both certs on loopback ports:

```console
$ REPO=$(git rev-parse --show-toplevel); LAB=$(mktemp -d)
$ cp "$REPO/docs/examples/lab/emudhra-ca-check/mk-fixture.sh" "$LAB/" && cd "$LAB" && bash mk-fixture.sh
wrote payments-api.pem, docs-site.pem, compromised-fixture.json in /tmp/tmp.XXXXXXXXXX
$ openssl s_server -accept 19460 -cert payments-api.pem -key payments-api.key -www -quiet >/dev/null 2>&1 &
$ openssl s_server -accept 19461 -cert docs-site.pem -key docs-site.key -www -quiet >/dev/null 2>&1 &
```

Then go to the skill, where the commands below run:

```console
$ cd "$REPO/.claude/skills/sre-emudhra-ca-check"
```

## What broke

Nothing in this lab is actually broken. `payments-api` is an ordinary, valid, unexpired certificate — the kind that would pass every other check in this pack (`sre-expiry-audit` would call it fine for a year). The only thing wrong with it, for the purposes of this lab, is that we're pretending it was issued by `EM DV TLS CA - G3B`, one of the 8 eMudhra intermediates revoked for a private-key compromise. That's the point of this skill: expiry, chain validity and trust-store status all say "fine," while the signing key is one anyone could reconstruct.

## What you'd type

> Check whether payments-api or docs-site on localhost chain through one of the revoked eMudhra intermediates.

## What the skill ran, and why

**1. Check both endpoints against the lab's synthetic "compromised" data** (`--data` overrides the bundled list, same flag the skill's own offline tests use):

```console
$ bash scripts/emudhra-ca-check.sh --data "$LAB/compromised-fixture.json" --timeout 10 localhost:19460 localhost:19461; echo "exit=$?"
COMPROMISED localhost:19460 1(leaf) CN=payments-api.shop.lab 71E1DFF3EB78A95E0858284FB09A303055F6B9A3D883923C022864BF115981D2
OK localhost:19461 1(leaf) CN=docs-site.shop.lab EBE35B21008AF41DD500020798BD02034D8413DC3AA015ABEA0DCFB4B23232A8
exit=1
```

`payments-api`'s fingerprint matches the fixture entry; `docs-site` doesn't, so it's `OK`. Exit 1 means at least one `COMPROMISED` finding — read the per-line status, not just the exit code, once you're checking more than one target.

**2. The same two certs against the real bundled list.** Neither is an actual eMudhra certificate, so both come back clean — this confirms the lab's "compromised" result in step 1 came from the fixture data, not from some property of the certs themselves:

```console
$ bash scripts/emudhra-ca-check.sh --timeout 10 localhost:19460 localhost:19461; echo "exit=$?"
OK localhost:19460 1(leaf) CN=payments-api.shop.lab 71E1DFF3EB78A95E0858284FB09A303055F6B9A3D883923C022864BF115981D2
OK localhost:19461 1(leaf) CN=docs-site.shop.lab EBE35B21008AF41DD500020798BD02034D8413DC3AA015ABEA0DCFB4B23232A8
exit=0
```

**3. Files work the same way**, for certs sitting in a repo or build artifact before they're deployed:

```console
$ bash scripts/emudhra-ca-check.sh --data "$LAB/compromised-fixture.json" --file "$LAB/payments-api.pem" "$LAB/docs-site.pem"; echo "exit=$?"
COMPROMISED /tmp/tmp.XXXXXXXXXX/payments-api.pem 1(leaf) CN=payments-api.shop.lab 71E1DFF3EB78A95E0858284FB09A303055F6B9A3D883923C022864BF115981D2
OK /tmp/tmp.XXXXXXXXXX/docs-site.pem 1(leaf) CN=docs-site.shop.lab EBE35B21008AF41DD500020798BD02034D8413DC3AA015ABEA0DCFB4B23232A8
exit=1
```

## The report (written in the skill's format)

```text
Scope checked: 2 lab endpoints (localhost:19460, :19461) and the equivalent 2 cert files.
Data file: lab fixture compromised-fixture.json (NOT the real eMudhra incident list; the
  bundled compromised-intermediates.json found no match on either, as expected for lab certs).

| status      | target           | position | subject                | sha256 (first 12)  |
| COMPROMISED | localhost:19460  | 1(leaf)  | CN=payments-api.shop.lab | 71E1DFF3EB78 |
| OK          | localhost:19461  | 1(leaf)  | CN=docs-site.shop.lab    | EBE35B21008A |

Finding: payments-api.shop.lab matches a serial/fingerprint flagged as issued by a revoked
  eMudhra intermediate (EM DV TLS CA - G3B in this fixture).
Not a TLS-only risk indicator by itself -- check whether this certificate authenticates
  anything beyond public-web TLS for this service (it doesn't, in this lab).
Next step: reissue from a CA not on the affected list, through sre-change-safety.
  No certificate was reissued, revoked or redeployed by this skill.
```

## The approval stop

This skill is read-only from start to finish. It never reissues, revokes or redeploys a certificate — it only reports a match. In a real incident, `payments-api`'s owning team would take this finding to [sre-change-safety](../../.claude/skills/sre-change-safety/SKILL.md) to propose and get approval for the reissue; since this is a lab fixture and not a real production certificate, there's no approved action to show here.

## Cleanup

```console
$ kill $(jobs -p); cd "$REPO" && rm -rf "$LAB"    # the directory holds private keys
```

## What to take from this

- Expiry, chain validity and trust-store status are all orthogonal to this specific risk: a certificate can be perfectly healthy by every other measure and still be signed with a reconstructable key.
- Always check the whole chain. The script fetches every certificate the server sends, by default — there's no leaf-only mode to forget to turn off.
- A match is a lead, not a verdict on severity: whether it matters hinges on what the certificate is used for (public web TLS vs. mTLS vs. code-signing trust), which this skill hands off rather than guesses at.
- The bundled `compromised-intermediates.json` is a snapshot. Before trusting a clean result for a real decision, cross-check against CCADB/OneCRL — the skill's own `SKILL.md` says so, and this lab's step 2 is a reminder of what "clean against this list" actually means.
