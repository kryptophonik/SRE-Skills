#!/usr/bin/env bash
# Read-only preflight: confirm identity, effective region, and Health API access.
# Usage: AWS_PROFILE=<profile> AWS_REGION=<region> ./preflight.sh
# Refs (2026-10-16): https://docs.aws.amazon.com/health/latest/ug/health-api.html
set -euo pipefail
# shellcheck source=SCRIPTDIR/_guard.sh
source "$(dirname "$0")/_guard.sh"
region="${AWS_REGION:-${AWS_DEFAULT_REGION:-$(aws configure get region || true)}}"
[[ -n "$region" ]] || { echo "No region: set AWS_REGION" >&2; exit 1; }
echo "profile=${AWS_PROFILE:-<default chain>} region=$region"
aws_ro sts get-caller-identity --region "$region" --output table
errf=$(mktemp); trap 'rm -f "$errf"' EXIT
health_region=us-east-1
if command -v dig >/dev/null; then
  cname=$(dig +short global.health.amazonaws.com CNAME || true)
  [[ "$cname" =~ health\.([a-z0-9-]+)\.amazonaws ]] && health_region="${BASH_REMATCH[1]}"
fi
if aws_ro health describe-events --region "$health_region" --max-items 1 >/dev/null 2>"$errf"; then
  echo "Health API: OK (region $health_region)"
elif grep -q SubscriptionRequiredException "$errf"; then
  echo "Health API: needs Business Support+/Enterprise/Unified Operations (or legacy Business/On-Ramp/Enterprise); use the Health Dashboard instead"
else
  echo "Health API: error: $(cat "$errf")"
fi
