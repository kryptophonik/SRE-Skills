
# Schedule and Escalation Review

## Safety gates (REQUIRED)

Follow [sre-safety-gates](../../sre-safety-gates/SKILL.md). This skill is **read-only**: GET calls only, with a read-only key where possible. Every fix (editing a schedule, adding an override, changing a policy or a user's contact methods) is a write. Draft the fix, then get approval.

Setup (`PD`, `OG`, `PD_HOST`, `OG_HOST`, `pd_get`, `og_get`): see [api-reference-pagerduty.md](api-reference-pagerduty.md) and [api-reference-opsgenie.md](api-reference-opsgenie.md). Set the EU hosts when the account is EU ([regions-and-auth.md](regions-and-auth.md)).

> Automated subset: `../scripts/pd_audit_schedules.sh` (PagerDuty checks 1, 2, 5, 6, 8) and `../scripts/og_oncall.sh` (empty Opsgenie schedules right now).

## Collect (read-only)

```bash
WIN="since=<ISO8601-now>&until=<ISO8601-now+28d>"   # review window; include the next DST change
# PagerDuty
pd_get /services services "include[]=escalation_policies" > pd_services.jsonl
pd_get /escalation_policies escalation_policies "include[]=services&include[]=targets" > pd_eps.jsonl
pd_get /schedules schedules > pd_schedules.jsonl
for s in $(jq -r .id pd_schedules.jsonl); do
  curl "${PD[@]}" "$PD_HOST/schedules/$s?$WIN&time_zone=UTC" > "pd_sched_$s.json"
  curl "${PD[@]}" "$PD_HOST/schedules/$s/overrides?$WIN" > "pd_ovr_$s.json"
done
pd_get /users users "include[]=contact_methods&include[]=notification_rules" > pd_users.jsonl
# Opsgenie
curl "${OG[@]}" "$OG_HOST/v2/schedules" > og_schedules.json
for s in $(jq -r '.data[].id' og_schedules.json); do
  curl "${OG[@]}" "$OG_HOST/v2/schedules/$s?identifierType=id" > "og_sched_$s.json"
  curl "${OG[@]}" "$OG_HOST/v2/schedules/$s/timeline?expand=base,forwarding,override&interval=1&intervalUnit=months" > "og_tl_$s.json"
  curl "${OG[@]}" "$OG_HOST/v2/schedules/$s/overrides" > "og_ovr_$s.json"
done
curl "${OG[@]}" "$OG_HOST/v2/escalations" > og_escalations.json
curl "${OG[@]}" "$OG_HOST/v2/teams" > og_teams.json
og_get "/v2/users?limit=100" > og_users.jsonl
for u in $(jq -r .id og_users.jsonl); do
  curl "${OG[@]}" "$OG_HOST/v2/users/$u/contacts" > "og_contacts_$u.json"
  curl "${OG[@]}" "$OG_HOST/v2/users/$u/notification-rules" > "og_rules_$u.json"
done
```

Keep the output files in a scratch directory and don't commit them. They contain names, emails and phone numbers.

## Checks

| # | Check | PagerDuty data | Opsgenie data | Flag when |
|---|---|---|---|---|
| 1 | Coverage gaps | `final_schedule.rendered_schedule_entries` in `pd_sched_*` | `og_tl_*` final timeline | Any interval in the window with no entry |
| 2 | Single-person layers | `schedule_layers[].users` | rotation `participants` in `og_sched_*` | A layer or rotation has 1 participant, or 1 person covers more than 50% of the window |
| 3 | Time zones / DST | schedule `time_zone`, layer `rotation_virtual_start`, `restrictions` | schedule `timezone`, rotation `startDate`, `timeRestriction` | Schedule TZ differs from team TZ; handoff at 00:00–03:00 local in a DST zone; window crosses a DST change and handoffs move or gap |
| 4 | Escalation loops / repeats | `num_loops` | escalation `repeat` (`waitInterval`, `count`) | 0 repeats with a single level; very high repeat count |
| 5 | Empty levels | `escalation_rules[].targets` empty, or every target schedule has gaps (check 1) | `rules[].recipient` missing or an empty schedule | Any level that can resolve to nobody |
| 6 | Orphan policies | EP with empty `services` | escalation not used by any team routing rule (check in UI or through team routing) | Unused policy (cleanup candidate) |
| 7 | Services without a usable policy | service whose EP fails check 5 | – | Service that can page nobody |
| 8 | Unreachable users | `contact_methods` empty, or `notification_rules` lack a high-urgency rule | `og_contacts_*` empty/disabled, `og_rules_*` empty | User on any schedule or EP who can't be notified |
| 9 | Overlapping overrides | `pd_ovr_*` entries whose start/end overlap | `og_ovr_*` overlap | Overlaps, or an override that assigns a user failing check 8 |
| 10 | Timeouts | `escalation_delay_in_minutes` | rule `delay.timeAmount` | Too short (paged before the person can ack, e.g. under 5 min) or too long for the service severity (e.g. over 30 min for SEV-1). These thresholds are team policy, not vendor limits |

Example jq for check 1 (PagerDuty):

```bash
jq -r '.schedule.final_schedule.rendered_schedule_entries
  | sort_by(.start) | . as $e
  | range(1; length) | select($e[.].start > $e[.-1].end)
  | "GAP \($e[.-1].end) -> \($e[.].start)"' pd_sched_<SCHEDULE_ID>.json
```

## Output

```markdown
# Schedule/escalation review — [account placeholder] — [window UTC]
| # | Severity | Object (type/name/ID) | Finding | Proposed fix (WRITE, needs approval) |
|---|---|---|---|---|
```

- Proposed fixes are drafts only. Apply them after approval, using the write snippets in api-reference-pagerduty.md / api-reference-opsgenie.md or the UI.

## Sources

- PagerDuty: https://developer.pagerduty.com/api-reference/ (Get schedule with `since`/`until`/`time_zone`, List overrides, List escalation policies `include[]`, List users `include[]=contact_methods,notification_rules`) · https://developer.pagerduty.com/docs/pagination · https://support.pagerduty.com/main/docs/service-regions
- Opsgenie: https://docs.opsgenie.com/docs/schedule-api · https://docs.opsgenie.com/docs/schedule-override-api · https://docs.opsgenie.com/docs/escalation-api · https://docs.opsgenie.com/docs/team-api · https://docs.opsgenie.com/docs/user-api · https://docs.opsgenie.com/docs/contact-api · https://docs.opsgenie.com/docs/notification-rule-api

## Unverified

- Opsgenie timeline `interval`/`intervalUnit` parameter names and exact escalation JSON field names (`repeat`, `delay.timeAmount`). These are from memory of the docs and weren't re-checked line by line.
- The thresholds in checks 2 and 10 are suggested defaults, not vendor rules.
