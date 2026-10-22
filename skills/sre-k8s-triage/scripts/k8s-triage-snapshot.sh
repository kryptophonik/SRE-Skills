#!/usr/bin/env bash
# Read-only Kubernetes triage snapshot. Never reads Secrets, never mutates.
# Usage: k8s-triage-snapshot.sh --context <ctx> -n <namespace> [-o <outdir>] [--tail N]
# Exit: 0 snapshot written, 1 context missing or unsafe output dir, 2 usage,
# 3 API server unreachable or pods unreadable (no snapshot; never reported as done).
set -euo pipefail

CTX="" NS="" OUT="" TAIL=200 RT="20s"
usage() { echo "usage: $0 --context <ctx> -n <namespace> [-o <outdir>] [--tail N]" >&2; exit 2; }
while [[ $# -gt 0 ]]; do
  case "$1" in
    --context) CTX="${2:-}"; shift 2 ;;
    -n|--namespace) NS="${2:-}"; shift 2 ;;
    -o|--out) OUT="${2:-}"; shift 2 ;;
    --tail) TAIL="${2:-}"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "unknown arg: $1" >&2; usage ;;
  esac
done
[[ -n "$CTX" && -n "$NS" ]] || { echo "refusing: --context and -n are required (no defaults)" >&2; usage; }
[[ "$TAIL" =~ ^[0-9]+$ ]] || { echo "--tail must be an integer" >&2; exit 2; }
command -v kubectl >/dev/null || { echo "kubectl not found" >&2; exit 1; }

kctl() { kubectl --context "$CTX" -n "$NS" --request-timeout="$RT" "$@"; }

# Context must exist in kubeconfig; never fall back to current-context.
kubectl config get-contexts "$CTX" >/dev/null 2>&1 || { echo "context '$CTX' not in kubeconfig" >&2; exit 1; }

# Refuse rather than write a snapshot full of connection errors.
kubectl --context "$CTX" --request-timeout=10s get --raw /version >/dev/null 2>&1 \
  || { echo "cannot reach the API server for context '$CTX'; no snapshot taken" >&2; exit 3; }

TS="$(date +%Y%m%dT%H%M%S)"
OUT="${OUT:-${TMPDIR:-/tmp}/k8s-triage/${CTX//[^A-Za-z0-9_.-]/_}_${NS}_${TS}}"
case "$(cd "$(dirname "$OUT")" 2>/dev/null && pwd || echo /)" in
  "$(git rev-parse --show-toplevel 2>/dev/null || echo /nonexistent)"*) echo "refusing: output dir is inside a git repo" >&2; exit 1 ;;
esac
mkdir -p "$OUT"; chmod 700 "$OUT"
echo "writing to $OUT" >&2

# Only redact inside "Environment:" blocks of describe pod.
redact_describe() {
  awk '
    /^[[:space:]]+Environment:/ {inenv=1; print; ind=match($0,/[^ ]/); next}
    inenv { cur=match($0,/[^ ]/); if (cur<=ind || $0 ~ /^[[:space:]]*(Mounts|Environment Variables from):/) {inenv=0} else { sub(/:[[:space:]].*/, ": <redacted>"); print; next } }
    {print}' | sed -E 's/((password|passwd|token|secret|apikey|api_key|authorization)[^:=]*[:=])[[:space:]]*[^[:space:]]+/\1 <redacted>/Ig'
}

FAILED=0
section() { # name, command...; failure of one section never aborts the run
  local name="$1"; shift
  if ! "$@" >"$OUT/$name.txt" 2>"$OUT/$name.err"; then echo "[warn] $name failed (see $name.err)" >&2; FAILED=$((FAILED+1)); fi
  [[ -s "$OUT/$name.err" ]] || rm -f "$OUT/$name.err"
}

{ echo "requested_context=$CTX namespace=$NS ts=$TS"; echo "kubeconfig_current_context=$(kubectl config current-context 2>/dev/null || echo none)"; } >"$OUT/00-context.txt"
section 01-pods        kctl get pods -o wide
[[ -s "$OUT/01-pods.err" ]] && ! [[ -s "$OUT/01-pods.txt" ]] && grep -qv 'No resources found' "$OUT/01-pods.err" \
  && { echo "cannot list pods in $NS (see $OUT/01-pods.err); snapshot incomplete" >&2; exit 3; }
section 02-events-warn kctl events --types=Warning
section 03-deploy      kctl get deploy,sts,ds,rs -o wide
section 04-svc-eps     kctl get svc,endpointslices
section 05-quota       kctl describe resourcequota
section 06-limitrange  kctl describe limitrange
section 07-hpa         kctl get hpa
section 08-pvc         kctl get pvc
if ! kctl top pods --containers >"$OUT/09-top.txt" 2>"$OUT/09-top.err"; then
  echo "metrics unavailable (metrics-server missing?)" >>"$OUT/09-top.txt"
fi

# Rollout status, non-blocking.
mkdir -p "$OUT/rollouts"
for d in $(kctl get deploy -o name 2>/dev/null || true); do
  kctl rollout status "$d" --watch=false >"$OUT/rollouts/${d#*/}.txt" 2>&1 || true
done

# Unhealthy pods: not Running/Succeeded, any container not ready, or restarts > 0.
mkdir -p "$OUT/pods"
BAD=()  # bash 3.2 compatible (no mapfile)
while IFS= read -r line; do [[ -n "$line" ]] && BAD+=("$line"); done < <(kctl get pods -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.phase}{"\t"}{range .status.containerStatuses[*]}{.ready}{","}{.restartCount}{" "}{end}{"\n"}{end}' 2>/dev/null \
  | awk -F'\t' '{bad=($2!="Running" && $2!="Succeeded"); n=split($3,c," "); for(i=1;i<=n;i++){split(c[i],f,","); if(f[1]=="false"||f[2]>0) bad=1} if(bad) print $1}' | head -20 || true)
for p in ${BAD[@]+"${BAD[@]}"}; do
  [[ -n "$p" ]] || continue
  kctl describe pod "$p" 2>&1 | redact_describe >"$OUT/pods/$p.describe.txt" || true
  kctl logs "$p" --all-containers --tail="$TAIL" --timestamps >"$OUT/pods/$p.log" 2>&1 || true
  kctl logs "$p" --all-containers --previous --tail="$TAIL" --timestamps >"$OUT/pods/$p.prev.log" 2>&1 || true
done

echo "NOTE: logs are not redacted; treat $OUT as sensitive. Secrets were not read." >"$OUT/README.txt"
echo "done: $OUT (${#BAD[@]} unhealthy pods captured, max 20; $FAILED sections failed)" >&2
