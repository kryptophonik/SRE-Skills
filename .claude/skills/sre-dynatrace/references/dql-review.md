# DQL review checklist (reference for sre-dynatrace)

Read-only. This checklist reads a query and suggests fixes; it runs nothing unless the user asks, and then only through `../scripts/dql.sh` (read-only).

Go through the query in this order and stop at the first real problem:

1. **Start command.** Metrics use `timeseries`, never `fetch`. Topology uses `smartscapeNodes`.
2. **Time range.** Is it bounded? `from: toTimestamp(...)` is wrong; use `timeframe: "start/end"`.
3. **Percentiles.** In `timeseries`, `percentile`/`median`/`percentRank` need `rollup:` (inside each function when using `{}`). In `summarize`, they must not have it.
4. **Arrays.** Any `==` on `k8s.*` fields of `dt.davis.problems`, or on another array field, becomes `in(field, {...})`. `arrayContains` does not exist. Iterative expressions go through `fieldsAdd` before `arrayMax`/`arraySum`.
5. **Problems.** `not(dt.davis.is_duplicate)` is present; status is `ACTIVE` or `CLOSED`; problem counts use distinct `display_id`.
6. **Field names.** Compare against [metrics-and-fields.md](metrics-and-fields.md). Anything not there: run `../scripts/check-fields.sh <object>` or tell the user to check with `| limit 1`.
7. **Entities.** `dt.entity.*` works but is deprecated; suggest `dt.smartscape.*`, keep the classic form only for older tenants.
8. **Units.** Service response time is microseconds.

Output: the corrected query, and one line per change saying why. If nothing is wrong, say "OK" and name anything you could not verify without a tenant.

Full table of mistakes: [dql-cheatsheet.md](dql-cheatsheet.md).

## Sources

- https://github.com/Dynatrace/dynatrace-for-ai/blob/main/skills/dt-dql-essentials/SKILL.md
- https://github.com/Dynatrace/dynatrace-for-ai/blob/main/skills/dt-obs-problems/SKILL.md
