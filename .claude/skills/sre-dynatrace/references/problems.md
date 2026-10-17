# Problem triage patterns

All queries start from the same base: bounded time, duplicates out.

Active problems, newest first:

```dql
fetch dt.davis.problems, from: now()-24h
| filter not(dt.davis.is_duplicate) and event.status == "ACTIVE"
| fields event.start, display_id, event.name, event.category,
    affected = smartscape.affected_entities[][id], root_cause_entity_name
| sort event.start desc
```

Count by category and status:

```dql
fetch dt.davis.problems, from: now()-7d
| filter not(dt.davis.is_duplicate)
| summarize problems = count(), by: {event.category, event.status}
```

Problems in one namespace (array field, so `in()`):

```dql
fetch dt.davis.problems, from: now()-24h
| filter not(dt.davis.is_duplicate) and in(k8s.namespace.name, {"payments"})
```

Problems touching AWS resources:

```dql
fetch dt.davis.problems, from: now()-24h
| filter not(dt.davis.is_duplicate)
| filter iAny(startsWith(smartscape.affected_entities[][type], "AWS_"))
```

Most frequent root causes over a week:

```dql
fetch dt.davis.problems, from: now()-7d
| filter not(dt.davis.is_duplicate) and isNotNull(root_cause_entity_name)
| summarize n = countDistinct(display_id), by: {root_cause_entity_name}
| sort n desc | limit 10
```

Notes:
- A problem can have several records over its life. When counting problems, count distinct `display_id`, or `dedup display_id` after sorting by time, rather than counting rows. (The countDistinct form is my suggestion; verify against your tenant.)
- A query that returns 0 for a namespace or cluster filter is often an `==` on an array field. Switch to `in()`.

## Sources

- https://github.com/Dynatrace/dynatrace-for-ai/blob/main/skills/dt-obs-problems/SKILL.md
- https://github.com/Dynatrace/dynatrace-for-ai/blob/main/skills/dt-dql-essentials/SKILL.md (in() on k8s.* array fields)
