# Examples: the skills on real lab incidents

Each page walks through one lab incident from start to finish: the setup, what you'd type, what the skill ran and why, the diagnosis, where it stopped for approval, the approved fix, verification and cleanup. Every lab runs locally on Docker or kind, with no cloud account.

| # | Scenario | Skills | What you'll see | Gate shown |
|---|---|---|---|---|
| 1 | [Crash-looping rollout on kind](01-k8s-crashloop-rollback.md) | sre-k8s-triage, sre-k8s-safe-remediation | Evidence snapshot, diagnosis from logs and events, server dry-run, rollback, verification | `rollout undo` held for approval |
| 2 | [Postgres lock chain and connection exhaustion](02-postgres-locks-and-connections.md) | sre-database-triage | Lock chain to its idle-in-transaction head, `db-ro.sh` refusing writes, a leaky pool, the ops role's missing grant | `pg_terminate_backend` for one pid, then for a filtered group |
| 3 | [Redis OOM and a MySQL lock wait](03-redis-oom-and-mysql-lock-wait.md) | sre-database-triage | "Store is full" vs "command is slow", the read-only allowlist refusing `CONFIG`, why not `allkeys-lru`, an InnoDB lock wait | `CONFIG SET` and MySQL `KILL`, each approved separately |
| 4 | [Four Kubernetes failure modes, read-only](04-k8s-failure-modes.md) | sre-k8s-triage | Read-only role preflight, OOMKilled, two kinds of Pending, a failing readiness probe, a refused write | Fixes held for approval; the read-only identity can't apply them anyway |
| 5 | [SLO burn-rate alerting](05-slo-burn-rate-alerting.md) | sre-slo-burn-rate-rules, sre-prometheus-grafana | Generated rules, `promtool test`, alerts firing in Prometheus, a silence with a comment | Silence held for approval |
| 6 | [Terraform plan, guard hook and drift](06-terraform-plan-and-drift.md) | sre-terraform | Plan risk summary, the guard hook blocking `apply`, drift check with revert option | `apply` held for approval; "accept drift" withheld for deletions |
| 7 | [TLS expiry audit](07-tls-expiry-audit.md) | sre-expiry-audit | Endpoints sorted into tiers, `--chain` finding an expiring intermediate, scriptable exit codes, a bug the lab caught | Read-only; renewals become separate approved changes |
| 8 | [DR restore drill](08-dr-restore-drill.md) | sre-dr-backup-test | Isolated restore, counts and checksums against the source, RTO/RPO record | Restore and cleanup held for approval |
| 9 | [Incident lifecycle on paper](09-incident-lifecycle.md) | sre-incident-command, sre-incident-communication, sre-postmortem-templates | Evidence timeline, decision log, update drafts, postmortem draft | Updates and postmortem stay unsent drafts |
| 10 | [The same crash-loop, but it's the real AI session](10-live-k8s-crashloop.md) | sre-k8s-triage, sre-k8s-safe-remediation | A genuinely captured transcript (not written in the skill's format): real `Skill` tool invocation, the manual-only gate refusing a model-initiated chain into the remediation skill, real divergence from example 1's script | Rollback held for a typed "approved, run it" |
| 11 | [eMudhra intermediate CA compromise check](11-emudhra-ca-check.md) | sre-emudhra-ca-check | A cert that's healthy by every other measure flagged for a reconstructable signing key; a synthetic fixture built from the lab cert's own fingerprint; checking the whole chain, not just the leaf | Read-only; reissue is a separate approved change |
| 12 | [Catching PHP2Shell, and the distro trap](12-php2shell-check.md) | sre-php2shell-check | A small fleet checked in one run: vulnerable, EOL-and-unresolved, and patched side by side; why a Debian/Ubuntu security backport can fool a naive version check | Read-only; the upgrade is a separate approved change |

## How to read these pages

- **Command output is real.** It comes from lab runs on 2026-10-22 (examples 10-12: 2026-10-23). Each page lists the tool versions, and marks trimmed output with `...`.
- **Diagnoses, plans and drafts are "written in the skill's format"** in examples 1-9, 11 and 12. They show the shape of the answer the skill asks for, not a word-for-word model reply. **Example 10 is the exception**: it's a genuine captured transcript from a real agent session, not reconstructed after the fact.
- **Lab values are placeholders.** Passwords, hosts and IPs are shown as `<admin password>`, `<app-host>`, `<pod-ip>` and so on. Keep real secrets in files or environment variables, never in a prompt or a command line.
- Lab files referenced by the pages are in [lab/](lab/). Screenshots are in [images/](images/) and are rendered from the same output shown on each page.

Start with the [getting-started guide](../getting-started.md) if you haven't installed the skills yet.
