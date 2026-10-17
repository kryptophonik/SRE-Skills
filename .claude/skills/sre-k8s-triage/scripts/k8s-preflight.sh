#!/usr/bin/env bash
# Read-only preflight: confirms context exists and shows the agent identity
# CANNOT read secrets, exec, port-forward, or delete. Exits 1 if it can.
# Usage: k8s-preflight.sh --context <ctx> -n <namespace> [--as <user|system:serviceaccount:ns:name>]
set -euo pipefail
CTX="" NS="" AS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --context) CTX="${2:-}"; shift 2 ;;
    -n|--namespace) NS="${2:-}"; shift 2 ;;
    --as) AS=(--as "${2:-}"); shift 2 ;;
    *) echo "usage: $0 --context <ctx> -n <ns> [--as <identity>]" >&2; exit 2 ;;
  esac
done
[[ -n "$CTX" && -n "$NS" ]] || { echo "refusing: --context and -n are required" >&2; exit 2; }
kubectl config get-contexts "$CTX" >/dev/null 2>&1 || { echo "context '$CTX' not in kubeconfig" >&2; exit 1; }
k() { kubectl --context "$CTX" -n "$NS" --request-timeout=15s ${AS[@]+"${AS[@]}"} "$@"; }

echo "context=$CTX namespace=$NS identity=${AS[1]:-<kubeconfig user>}"
fail=0
check() { # expect: yes|no, verb, resource
  local want="$1"; shift
  local got; got="$(k auth can-i "$@" 2>/dev/null || true)"; got="${got:-no}"
  local mark="OK"; [[ "$got" == "$want" ]] || { mark="FAIL"; fail=1; }
  printf '%-5s can-i %-28s => %-3s (want %s)\n' "$mark" "$*" "$got" "$want"
}
check yes get pods
check yes list events
check yes get pods/log
check no  get secrets
check no  list secrets
check no  create pods/exec
check no  create pods/attach
check no  create pods/portforward
check no  delete pods
check no  patch deployments
check no  create deployments
check no  delete namespaces
exit "$fail"
