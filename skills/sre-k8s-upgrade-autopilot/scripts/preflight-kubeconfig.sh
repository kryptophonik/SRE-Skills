#!/usr/bin/env bash
# Builds a short-lived kubeconfig for the upgrade-preflight ServiceAccount from references/rbac-preflight.yaml,
# so the preflight runs as that get/list-only identity instead of as an admin.
# This CREATES A CREDENTIAL (a Kubernetes TokenRequest via kubectl create token): run it only after approval.
# The token is written to a mode-600 kubeconfig in a mode-700 directory and is never printed.
#
# Usage: bash scripts/preflight-kubeconfig.sh --context <admin-ctx> [--duration 1h] [--dir <new-dir>]
#   --context   admin context that can create tokens for kube-system/upgrade-preflight (required)
#   --duration  token lifetime, 10m to 24h (default 1h); the API server may issue a shorter one
#   --dir       directory to create for the kubeconfig (default: a new mktemp dir under ${TMPDIR:-/tmp})
# Prints the kubeconfig path; the context inside it is upgrade-preflight-ro. Delete the directory when done.
#

set -euo pipefail

CTX="" DUR="1h" DIR=""
usage() { sed -n '7,11p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }
while [ $# -gt 0 ]; do
  case "$1" in
    --context) CTX="${2:-}"; shift 2 ;;
    --duration) DUR="${2:-}"; shift 2 ;;
    --dir) DIR="${2:-}"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "unknown argument: $1" >&2; usage ;;
  esac
done
[ -n "$CTX" ] || { echo "refusing: --context <admin-ctx> is required; the current context is never assumed" >&2; exit 2; }
[[ "$DUR" =~ ^([1-9][0-9]*)(m|h)$ ]] || { echo "refusing: --duration must look like 30m or 1h" >&2; exit 2; }
MIN="${BASH_REMATCH[1]}"; [ "${BASH_REMATCH[2]}" = h ] && MIN=$((MIN * 60))
{ [ "$MIN" -ge 10 ] && [ "$MIN" -le 1440 ]; } || { echo "refusing: --duration must be between 10m and 24h" >&2; exit 2; }
[ -z "$DIR" ] || [ ! -e "$DIR" ] || { echo "refusing: --dir $DIR already exists" >&2; exit 2; }
command -v kubectl >/dev/null 2>&1 || { echo "kubectl is required" >&2; exit 2; }
kubectl config get-contexts "$CTX" >/dev/null 2>&1 || { echo "refusing: context '$CTX' is not in the kubeconfig" >&2; exit 2; }

# Only the API server address and its CA are read from the admin context; its own credentials are not copied.
SERVER="$(kubectl config view --raw --minify --context "$CTX" -o jsonpath='{.clusters[0].cluster.server}')"
CADATA="$(kubectl config view --raw --minify --context "$CTX" -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')"
CAFILE="$(kubectl config view --raw --minify --context "$CTX" -o jsonpath='{.clusters[0].cluster.certificate-authority}')"
[ -n "$SERVER" ] || { echo "could not read the API server address for '$CTX'" >&2; exit 2; }
if [ -n "$CADATA" ]; then CA="certificate-authority-data: \"$CADATA\""
elif [ -n "$CAFILE" ]; then CA="certificate-authority: \"$CAFILE\""
else echo "refusing: '$CTX' has no cluster CA; not writing a kubeconfig that skips TLS verification" >&2; exit 2; fi

umask 077
TOKEN="$(kubectl --context "$CTX" -n kube-system create token upgrade-preflight --duration "$DUR")"
[ -n "$TOKEN" ] || { echo "kubectl create token returned nothing (is references/rbac-preflight.yaml applied?)" >&2; exit 1; }
if [ -n "$DIR" ]; then mkdir -p "$DIR"; else DIR="$(mktemp -d "${TMPDIR:-/tmp}/k8sup-preflight-kc.XXXXXX")"; fi
chmod 700 "$DIR"
KC="$DIR/kubeconfig"
printf 'apiVersion: v1\nkind: Config\nclusters:\n- name: upgrade-preflight\n  cluster: {server: "%s", %s}\nusers:\n- name: upgrade-preflight\n  user: {token: "%s"}\ncontexts:\n- name: upgrade-preflight-ro\n  context: {cluster: upgrade-preflight, user: upgrade-preflight}\ncurrent-context: upgrade-preflight-ro\n' \
  "$SERVER" "$CA" "$TOKEN" > "$KC"
unset TOKEN
echo "$KC"
