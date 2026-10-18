#!/usr/bin/env bash
# Self-test for gen-burn-rate-rules.py. Needs promtool (Prometheus 3.x) on PATH or PROMTOOL=/path/to/promtool.
# Writes only to a temp dir. Exit 0 = all checks passed.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REF="$HERE/../references"
GEN="$HERE/gen-burn-rate-rules.py"
PROMTOOL="${PROMTOOL:-promtool}"
command -v "$PROMTOOL" >/dev/null || { echo "promtool not found; set PROMTOOL=/path/to/promtool" >&2; exit 2; }
T="$(mktemp -d)"; trap 'rm -rf -- "${T:?}"' EXIT
pass=0; fail=0
expect_ok()   { local d="$1"; shift; if "$@" >/dev/null 2>&1; then echo "PASS: $d"; pass=$((pass+1)); else echo "FAIL: $d"; fail=$((fail+1)); fi; }
expect_fail() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then echo "FAIL: $d"; fail=$((fail+1)); else echo "PASS: $d"; pass=$((pass+1)); fi; }

ERR='http_requests_total{job="example-svc",code=~"5.."}'
TOT='http_requests_total{job="example-svc"}'
gen() { "$GEN" --errors "$ERR" --total "$TOT" "$@"; }

# 1. Reference file is exactly what the generator produces.
gen --slo-name example-availability --objective 0.999 --out "$T/ref.yml"
expect_ok "reference rules match generator output" diff -u "$REF/slo-burn-rate.rules.yml" "$T/ref.yml"

# 2. Lint + unit tests on the reference.
expect_ok "promtool check rules --lint=all --lint-fatal (reference)" "$PROMTOOL" check rules --lint=all --lint-fatal "$T/ref.yml"
cp "$REF/slo-burn-rate.test.yml" "$T/"; cp "$T/ref.yml" "$T/slo-burn-rate.rules.yml"
expect_ok "promtool test rules (7 scenarios)" "$PROMTOOL" test rules "$T/slo-burn-rate.test.yml"

# 3. Mutation checks: the unit tests must catch wrong thresholds.
for m in 's/(14.4 \* 0.001)/(144 * 0.001)/' 's/(6 \* 0.001)/(60 * 0.001)/' 's/(1 \* 0.001)/(10 * 0.001)/' 's/ratio_rate5m{slo/ratio_rate1h{slo/'; do
  sed "$m" "$T/ref.yml" > "$T/slo-burn-rate.rules.yml"
  expect_fail "mutation detected: $m" "$PROMTOOL" test rules "$T/slo-burn-rate.test.yml"
done

# 4. Variants must lint cleanly.
expect_ok "variant objective=0.99" gen --slo-name v1 --objective 0.99 --out "$T/v1.yml"
expect_ok "variant objective=0.9995 by=job,namespace interval=1m" gen --slo-name v2 --objective 0.9995 --by job,namespace --interval 1m --out "$T/v2.yml"
expect_ok "variant by='' period=28d for=1m" gen --slo-name v3 --objective 0.999 --by '' --period 28d --for 1m --out "$T/v3.yml"
expect_ok "variant period=4w by=service runbook placeholder" gen --slo-name v4 --objective 0.995 --by service --period 4w --runbook-url 'https://runbooks.example.com/slo/<slo-name>' --out "$T/v4.yml"
for i in 1 2 3 4; do expect_ok "promtool lint variant $i" "$PROMTOOL" check rules --lint=all --lint-fatal "$T/v$i.yml"; done
expect_ok "28d period rescales 14.4x to 13.44x" grep -q '(13.44 \* 0.001)' "$T/v3.yml"
expect_ok "empty --by produces plain sum()" grep -q '^          sum (rate(' "$T/v3.yml"
expect_ok "4w runbook placeholder substituted" grep -q 'runbooks.example.com/slo/v4"' "$T/v4.yml"

# 5. Low objective warns that tiers can never fire (SRE Workbook, "Extreme Availability Goals").
gen --slo-name low --objective 0.9 --out "$T/low.yml" 2>"$T/low.err"
expect_ok "objective 0.9 warns about unreachable tiers" grep -q 'can never fire' "$T/low.err"

# 6. Bad input is rejected.
for args in "--objective 99.9" "--objective 1" "--objective 0" "--objective abc" "--by slo" "--by bad-label" "--period 30x" "--for soon"; do
  # shellcheck disable=SC2086
  expect_fail "rejected: $args" gen --slo-name x --objective 0.999 $args
done
expect_fail "rejected: selector with [range]" "$GEN" --slo-name x --objective 0.999 --errors "${ERR}[5m]" --total "$TOT"
expect_fail "rejected: unbalanced braces" "$GEN" --slo-name x --objective 0.999 --errors 'http_requests_total{job="a"' --total "$TOT"
expect_fail "rejected: quote in --slo-name" gen --slo-name 'x"y' --objective 0.999

echo "== $pass passed, $fail failed"
[ "$fail" -eq 0 ]
