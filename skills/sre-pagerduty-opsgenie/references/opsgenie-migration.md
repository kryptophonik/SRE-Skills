
# Opsgenie Migration

> **Time-bounded reference. Remove after 2027-04-05** (Opsgenie end of support). `OG_HOST` always includes the scheme (`https://api.opsgenie.com`, EU `https://api.eu.opsgenie.com`), as in [api-reference-opsgenie.md](api-reference-opsgenie.md). Use `../scripts/og_export.sh` for exports: it uses `umask 077` (integration exports contain API keys), a GET-only guard and 429 backoff.

## Safety gates (REQUIRED)

Follow [sre-safety-gates](../../sre-safety-gates/SKILL.md). Export is read-only (GET only). Creating schedules, policies, services or integrations in the target, rerouting monitors, and disabling Opsgenie integrations are all writes. Draft them, then get approval. Never test with production routing.

## Key dates (official)

- **End of sale: June 4, 2025.** No new purchases or sign-ups, and no edition upgrades or downgrades.
- **End of support: April 5, 2027.** Access is shut off, and Opsgenie data that hasn't been moved is **deleted**.
- Source: https://www.atlassian.com/licensing/opsgenie · https://www.atlassian.com/software/opsgenie/migration

## Choose a path

| Path | What it is | Tooling |
|---|---|---|
| Jira Service Management (JSM) Cloud | Atlassian's main path. Opsgenie features become JSM "Operations" | Atlassian's in-app migration tool, which you schedule from Opsgenie |
| Compass | Same Operations platform, licensed through Compass. Alerts, schedules, escalations, routing rules, integrations and policies are shared with JSM on the same site | Same Atlassian migration tool; you pick one primary destination product |
| PagerDuty | Third-party move | PagerDuty offers Professional Services migration ("as-is" config migration under a promotional offer). There is no self-serve PagerDuty importer documented in PagerDuty's developer docs (unverified; see below) |

Atlassian sources:
- https://support.atlassian.com/opsgenie/docs/schedule-an-opsgenie-migration/
- https://support.atlassian.com/opsgenie/docs/managing-operations-in-compass-and-jira-service-management-at-the-same-time/
- https://support.atlassian.com/opsgenie/docs/prepare-for-data-migration-after-scheduling-your-date/
- https://support.atlassian.com/opsgenie/docs/feature-changes-and-deprecations-in-jira-service-management/

PagerDuty sources: https://www.pagerduty.com/opsgenie-migration-offer-details/ · https://www.pagerduty.com/resources/aiops/checklist/opsgenie-migration-checklist/

Atlassian notes that matter for planning:
- The migration tool only targets Atlassian **Cloud**, not JSM Data Center.
- Before migrating, upgrade the deprecated items: global integrations, **Heartbeats v1**, **Groups**, and **Policies v1** (convert to team-based policies). Deprecated policy configs that aren't converted won't carry over.
- After migration, heartbeats move to atlassian.net domains, so update any scripts that use opsgenie.net heartbeat emails. There is a 2,000-heartbeat-per-site cap. Source: https://support.atlassian.com/opsgenie/docs/advanced-alert-configurations-after-migration/
- The post-migration Migration Guide in JSM is available for 120 days.

## Concept mapping

| Opsgenie | JSM / Compass Operations | PagerDuty |
|---|---|---|
| Team | Team (Operations) | Team |
| Schedule | On-call schedule | Schedule |
| Rotation | Rotation | Schedule layer |
| Override | Override | Override |
| Escalation | Escalation policy | Escalation policy (rules + `num_loops`) |
| Routing rule (team) | Routing rule | Service + Event Orchestration / service routing (no direct 1:1) |
| Integration (API, email, tool) | Integration | Service integration (Events API v2 integration key, email, vendor) |
| Heartbeat | Heartbeat (team-based) | No native heartbeat. Use an external dead-man's-switch or the monitoring tool (unverified) |
| Alert policy (team, v2) | Policies, plus JSM Automation for action policies | Event Orchestration rules |
| Notification policy | Team notification policy | Service urgency / support hours plus user notification rules (partial) |
| User + contact methods | Atlassian account + contact methods | User + contact methods |
| Notification rules | Notification preferences | User notification rules (high/low urgency) |
| Alert | Alert | Alert → Incident |
| Incident (Opsgenie Incident) | JSM incident | Incident |

Treat the PagerDuty column as a modeling guide. Confirm each mapping in the PagerDuty docs before you build.

> Script: `../scripts/og_export.sh --out DIR` does this export for you (GET only, follows pagination, output dir mode 700).

## Export (read-only)

Set `OG_HOST` (`https://api.opsgenie.com` or EU `https://api.eu.opsgenie.com`) and `OG_API_KEY` (an API integration key with read access). Use `og_get` from [api-reference-opsgenie.md](api-reference-opsgenie.md), which follows `paging.next`. GET only.

```bash
OUT=./og-export-$(date -u +%Y%m%dT%H%MZ); mkdir -p "$OUT"
for p in teams schedules escalations heartbeats integrations; do
  curl -sS -H "Authorization: GenieKey $OG_API_KEY" "$OG_HOST/v2/$p" > "$OUT/$p.json"
done
og_get "/v2/users?limit=100" > "$OUT/users.jsonl"
for s in $(jq -r '.data[].id' "$OUT/schedules.json"); do
  curl -sS -H "Authorization: GenieKey $OG_API_KEY" "$OG_HOST/v2/schedules/$s" > "$OUT/schedule_$s.json"
  curl -sS -H "Authorization: GenieKey $OG_API_KEY" "$OG_HOST/v2/schedules/$s/overrides" > "$OUT/overrides_$s.json"
done
for u in $(jq -r .id "$OUT/users.jsonl"); do
  curl -sS -H "Authorization: GenieKey $OG_API_KEY" "$OG_HOST/v2/users/$u/contacts" > "$OUT/contacts_$u.json"
  curl -sS -H "Authorization: GenieKey $OG_API_KEY" "$OG_HOST/v2/users/$u/notification-rules" > "$OUT/rules_$u.json"
done
for i in $(jq -r '.data[].id' "$OUT/integrations.json"); do
  curl -sS -H "Authorization: GenieKey $OG_API_KEY" "$OG_HOST/v2/integrations/$i" > "$OUT/integration_$i.json"
done
# Team routing rules and team alert policies: see "Unverified" below.
```

The export contains personal data (phone numbers, emails) and integration API keys. Store it encrypted, don't commit it, and delete it after the migration.

Sources: https://docs.opsgenie.com/docs/team-api · https://docs.opsgenie.com/docs/schedule-api · https://docs.opsgenie.com/docs/schedule-override-api · https://docs.opsgenie.com/docs/escalation-api · https://docs.opsgenie.com/docs/heartbeat-api · https://docs.opsgenie.com/docs/integration-api · https://docs.opsgenie.com/docs/user-api · https://docs.opsgenie.com/docs/contact-api · https://docs.opsgenie.com/docs/notification-rule-api · https://docs.opsgenie.com/docs/pagination

## Pre-cutover checklist

- [ ] Path chosen (JSM / Compass / PagerDuty), owner and date set well before 2027-04-05
- [ ] Export done and inventory counted (teams, schedules, rotations, overrides, escalations, integrations, heartbeats, policies, users)
- [ ] Deprecated items upgraded (Atlassian path): global integrations, Heartbeats v1, Groups, Policies v1
- [ ] Every monitoring source that sends to Opsgenie listed, with how it's reconfigured
- [ ] Every user has a working contact method and notification rule in the target (run [schedule-escalation-review.md](schedule-escalation-audit.md) on the target)
- [ ] Scripts that reference opsgenie.net heartbeat emails or `api.opsgenie.com` listed
- [ ] Sandbox service/team and test user created in the target (see test plan)
- [ ] Rollback owner named; Opsgenie integrations left **enabled** until sign-off

## Parallel run / test plan (no real person paged)

1. Create a **sandbox** service/team in the target. Its escalation policy targets only a test user whose contact method is a test inbox or a team-owned test device.
2. Send synthetic events only to the sandbox routing key or integration. Never send them to a production service. With PagerDuty, use Events API v2 with a fixed `dedup_key`, then resolve ([events-api-v2.md](events-api-v2.md); PAGES PEOPLE, so it needs approval even in sandbox).
3. Compare the schedules: render the target schedule and the Opsgenie timeline for the same 4-week window, including a DST change, and diff who is on call.
4. Mirror alerts (optional): have monitoring send to both systems, with the target routed to a non-paging service or a low-urgency, notify-nobody policy for 1–2 weeks. Compare alert counts and dedup.
5. Run the schedule-escalation-review checks on the target and fix findings (writes, with approval).
6. Sign-off criteria: no coverage gaps, alert parity is acceptable, and every on-call user has acknowledged a sandbox test.

## Cutover checklist

- [ ] Announce the window and the "who is on call" source of truth to responders
- [ ] Switch each monitoring source to the target's production integration, one service at a time (WRITE)
- [ ] Verify one low-risk real alert per service reaches the right on-call person (with that person's agreement)
- [ ] Keep Opsgenie integrations enabled but not paging, or as a fallback, for an agreed period
- [ ] Update runbooks, the `pagerduty-opsgenie` skill config, scripts and heartbeat endpoints
- [ ] After sign-off, disable the Opsgenie integrations (WRITE). Keep the export until the retention policy says delete

## Rollback

- Trigger: missed or misrouted pages, a coverage gap, or a target outage during the cutover window.
- Point monitoring back at the Opsgenie integrations, which were kept enabled (WRITE, approval from the IC).
- Re-check the Opsgenie on-call with the who-is-on-call API.
- Rollback is only possible before 2027-04-05. After that, Opsgenie is inaccessible and data that wasn't migrated is deleted.

## Unverified

- **PagerDuty tooling:** the only official sources I found describe Professional Services migration and a promotional offer (https://www.pagerduty.com/opsgenie-migration-offer-details/). PagerDuty community posts mention "automated migration utilities", but I found no self-serve importer in PagerDuty's official docs.
- **Opsgenie team routing rules and team alert policies export endpoints:** the docs pages I fetched listed only `/v1/policies` (the deprecated Policy API). Confirm the v2 team-policy and routing-rule endpoints before you use them.
- **PagerDuty "no native heartbeat":** not confirmed against PagerDuty docs.
- **Compass licensing details** beyond "one primary destination product".

## Migration workflow

1. **Pick the path:** JSM Cloud, Compass (Atlassian's in-app migration tool), or PagerDuty. See the sections below.
2. **Export, read-only:** `../scripts/og_export.sh` --out <secure-dir>` (env `OG_API_KEY`, `OG_REGION=us|eu`). The output contains PII, so store it encrypted and never commit it.
3. **Inventory:** count teams, schedules, rotations, overrides, escalations, integrations, heartbeats, policies and users. Flag deprecated items (Heartbeats v1, Groups, Policies v1, global integrations).
4. **Map** each object to the target using the concept table in the reference.
5. **Build the target.** These are writes: draft each change, then get approval.
6. **Parallel run in a sandbox:** a test service and a test user only. Compare schedules over a window that includes a DST change.
7. **Audit the target** with `sre-oncall-audit` before cutover.
8. **Cutover service by service**, keeping Opsgenie as the rollback path until sign-off and never past 2027-04-05.

### Migration output

- Migration plan: path, inventory counts, mapping table, gaps and deprecated items, cutover order, rollback owner, and approvals recorded (who, what, when)
