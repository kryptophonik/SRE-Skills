#!/usr/bin/env bash
# Read-only preflight for the gcp skill. Writes nothing, calls no mutating APIs.
# Usage: PROJECT_ID=<PROJECT_ID> scripts/preflight.sh
# Sources (fetched 2026-10-16, gcloud SDK 589.0.0 / 2026-10-13):
#   gcloud version     https://cloud.google.com/sdk/gcloud/reference/version (Last updated 2025-05-07 UTC)
#   gcloud config get  https://cloud.google.com/sdk/gcloud/reference/config/get (Last updated 2026-10-13 UTC)
#   gke-gcloud-auth-plugin --version
#     https://cloud.google.com/kubernetes-engine/docs/how-to/cluster-access-for-kubectl (Last updated 2026-10-13 UTC)
set -euo pipefail

if [[ -z "${PROJECT_ID:-}" ]]; then
  echo "ERROR: set PROJECT_ID=<PROJECT_ID>" >&2
  exit 2
fi
command -v gcloud >/dev/null 2>&1 || { echo "ERROR: gcloud not found" >&2; exit 2; }

echo "== gcloud version"
gcloud version

account="$(gcloud config get account 2>/dev/null || true)"
active_project="$(gcloud config get project 2>/dev/null || true)"
impersonate="$(gcloud config get auth/impersonate_service_account 2>/dev/null || true)"
echo "== account:            ${account:-<none>}"
echo "== impersonating:      ${impersonate:-${CLOUDSDK_AUTH_IMPERSONATE_SERVICE_ACCOUNT:-<none>}}"
echo "== active project:     ${active_project:-<none>}"
echo "== requested project:  ${PROJECT_ID}"

if [[ "${active_project}" != "${PROJECT_ID}" ]]; then
  echo "ERROR: active project '${active_project:-<none>}' != PROJECT_ID '${PROJECT_ID}'. Refusing to continue." >&2
  exit 3
fi

if command -v gke-gcloud-auth-plugin >/dev/null 2>&1; then
  echo "== gke-gcloud-auth-plugin: $(gke-gcloud-auth-plugin --version 2>&1 | head -n1)"
else
  echo "WARN: gke-gcloud-auth-plugin not installed; kubectl against GKE will not work." >&2
fi
echo "OK: preflight passed (read-only)."
