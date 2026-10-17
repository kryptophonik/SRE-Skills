---
name: sre-slo-burn-rate-rules
description: "Use when asked to create or fix Prometheus SLO burn-rate alerts: generate 4-tier multiwindow rules from an SLO target and counter selectors, then lint and unit-test with promtool. Files for review only; never deploys."
---

# SLO burn-rate rules

## Safety gates (REQUIRED)

1. Read-only diagnosis first.
2. Propose each change with risk (low/med/high) and reversibility.
3. Wait for explicit human approval before any prod-changing command, MCP write tool, or external post.
4. Act only as approved, verify, and stop and escalate if anything gets worse.

Full rules: [sre-safety-gates](../sre-safety-gates/SKILL.md). Process and policy: `sre-slo-alerting`. Script and references: `sre-prometheus-grafana`.

Requires `sre-prometheus-grafana` installed alongside (sibling folder).

## Steps

1. Get from the user, or ask: SLO name, objective (a ratio such as `0.999`), the **bad-events** counter selector, the **all-events** counter selector, the labels to keep (default `job`), and the SLO period (default `30d`). Check that the metric and label names exist (`promtool query series "$PROM_URL" --match='<selector>'`), and don't guess `code` vs `status`.
2. Generate:
   ```bash
   python3 ../sre-prometheus-grafana/scripts/gen-burn-rate-rules.py \
     --slo-name <name> --objective <0.999> \
     --errors '<metric>{job="<svc>",code=~"5.."}' --total '<metric>{job="<svc>"}' \
     --by job --runbook-url 'https://runbooks.example.com/slo/<slo-name>' --out slo-<name>.rules.yml
   ```
   If the script warns "can never fire", tell the user. With objectives of 99% or lower, the 14.4x tier can't trigger (SRE Workbook, "Extreme Availability Goals").
3. Validate: `promtool check rules --lint=all --lint-fatal slo-<name>.rules.yml`.
4. Unit-test: copy [slo-burn-rate.test.yml](../sre-prometheus-grafana/references/slo-burn-rate.test.yml). Point `rule_files` at the new file and set the series names, labels, `slo` value and annotations to match, then run `promtool test rules <test>.yml`. Keep all 7 scenarios: healthy, fast burn, slow burn, reset, 3d tier, 1h tier only, 6h tier only.
5. Output the rule file, the test file, both promtool results, and the alert routing note: the page alert is `severity=page` and the ticket alert is `severity=ticket`, both labelled `slo`. Inhibit the ticket while the page fires (`equal: [slo]`).
6. Stop. Changing a live Prometheus or rule repo goes through Git/CI with approval (`sre-safety-gates`). Never call `/-/reload`.

## Output

- Rule file, test file, `promtool check` and `promtool test` results, routing/inhibition note
