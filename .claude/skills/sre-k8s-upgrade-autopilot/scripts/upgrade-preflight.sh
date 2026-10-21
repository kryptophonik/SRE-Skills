#!/usr/bin/env bash
# Kubernetes minor-version upgrade preflight for EKS, GKE, AKS and conformant clusters.
# Its own kubectl calls are get, list and API discovery only (get / get --raw / api-versions / version);
# tests/run-tests.sh --kind checks this against the API server audit log. Optional kubent/pluto make their own list calls.
# Every call is written to <out>/raw/calls.log so the call set can be audited.
#
# Usage: bash scripts/upgrade-preflight.sh --context <ctx> --target <1.xx> [--out <dir>] [--no-tools] [--with-pluto]
#        bash scripts/upgrade-preflight.sh --context <name> --target <1.xx> --fixtures <dir> [--out <dir>]
#   (both forms also take --pool-label <node-label-key> and --deprecated-traffic-checked)
#   --context   kubeconfig context to read (required; the current context is never used)
#   --target    target minor version, for example 1.32
#   --out       output directory (default: a new ${TMPDIR:-/tmp}/k8sup-<context>-<target>-<UTC timestamp>.XXXXXX)
#   --fixtures  analyse recorded raw/*.json from an earlier run instead of calling the cluster
#   --no-tools  skip kubent even if it is installed
#   --pool-label  node label whose value names the pool (kind, kubeadm, custom pools); default: provider labels
#   --with-pluto  also run pluto detect-api-resources. It lists every resource type, including Secrets and
#               ConfigMaps (seen in our audit log), so use it only with the references/rbac-preflight.yaml identity
#   --deprecated-traffic-checked  you confirmed in the audit log or provider insights that nothing still calls the
#               removed APIs the deprecated-API metric lists; that cumulative counter then becomes WARN, not BLOCKER
# Exit: 0 no blockers (GO or GO-WITH-WARNINGS), 1 NO-GO, 2 usage error or refused, 3 cluster unreachable.
#

set -euo pipefail

CTX="" TARGET="" OUT="" FIX="" PLABEL="" PLABEL_SKIPPED=0 TOOLS=1 PLUTO=0 TRAFFIC_OK=false TIMEOUT="${PREFLIGHT_TIMEOUT:-30s}"
usage() { sed -n '6,19p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }
while [ $# -gt 0 ]; do
  case "$1" in
    --context) CTX="${2:-}"; shift 2 ;;
    --target) TARGET="${2:-}"; shift 2 ;;
    --out) OUT="${2:-}"; shift 2 ;;
    --fixtures) FIX="${2:-}"; shift 2 ;;
    --pool-label) PLABEL="${2:-}"; shift 2 ;;
    --no-tools) TOOLS=0; shift ;;
    --with-pluto) PLUTO=1; shift ;;
    --deprecated-traffic-checked) TRAFFIC_OK=true; shift ;;
    -h|--help) usage ;;
    *) echo "unknown argument: $1" >&2; usage ;;
  esac
done
[ -n "$CTX" ] || { echo "refusing: --context <ctx> is required; the current kubeconfig context is never assumed" >&2; exit 2; }
[[ "$TARGET" =~ ^v?1\.[0-9]+$ ]] || { echo "refusing: --target must look like 1.32" >&2; exit 2; }
TARGET="${TARGET#v}"; TMINOR="${TARGET#1.}"
[ -z "$PLABEL" ] || [[ "$PLABEL" =~ ^[A-Za-z0-9][A-Za-z0-9._/-]*$ ]] || { echo "refusing: --pool-label must be a node label key such as node.example.com/pool" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; exit 2; }

HERE="$(cd "$(dirname "$0")" && pwd)"
REMOVED="$HERE/../references/removed-apis.json"
SUPPORT="$HERE/../references/support-status.json"
NOW="${PREFLIGHT_NOW:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"   # PREFLIGHT_NOW pins the clock for tests only

# Validate everything before creating any directory: a refused run leaves nothing behind.
if [ -n "$FIX" ]; then
  [ -d "$FIX" ] || { echo "fixtures dir not found: $FIX" >&2; exit 2; }
else
  command -v kubectl >/dev/null 2>&1 || { echo "kubectl is required" >&2; exit 2; }
  kubectl config get-contexts "$CTX" >/dev/null 2>&1 || { echo "refusing: context '$CTX' is not in the kubeconfig" >&2; exit 2; }
fi
# Default output: mktemp -d adds a random suffix, so two runs in the same second never share a directory.
if [ -z "$OUT" ]; then
  OUT="$(umask 077; mktemp -d "${TMPDIR:-/tmp}/k8sup-${CTX//[^A-Za-z0-9_.-]/_}-$TARGET-$(date -u +%Y%m%dT%H%M%SZ).XXXXXX")" || { echo "cannot create an output directory under ${TMPDIR:-/tmp}" >&2; exit 2; }
fi
RAW="$OUT/raw"
( umask 077; mkdir -p "$RAW" )
[ -n "$FIX" ] || : > "$RAW/calls.log"

# Restricted kubectl wrapper: anything other than get / api-versions / api-resources / version is refused.
k() {
  case "$1" in
    get|api-versions|api-resources|version) ;;
    *) echo "refusing non-read kubectl verb: $1" >&2; exit 2 ;;
  esac
  printf '%s\n' "$*" >> "$RAW/calls.log"
  kubectl --context "$CTX" --request-timeout="$TIMEOUT" "$@"
}

# collect <name> <jq-trim-filter> <kubectl args...>
# Live: run kubectl, keep only the fields the analysis needs (no env, no data, no secrets), save raw/<name>.json.
# Fixtures: copy <fixtures>/<name>.json. A failed call is saved as {"error": "..."} and reported as "could not check".
collect() {
  local name="$1" filter="$2" err; shift 2
  if [ -n "$FIX" ]; then
    if [ -f "$FIX/$name.json" ]; then cp "$FIX/$name.json" "$RAW/$name.json"
    else printf '{"error":"not recorded in fixtures"}\n' > "$RAW/$name.json"; fi
    return 0
  fi
  if k "$@" -o json 2>"$RAW/.err" | jq -c "$filter" > "$RAW/$name.json.tmp" 2>>"$RAW/.err"; then
    mv "$RAW/$name.json.tmp" "$RAW/$name.json"
  else
    err="$(tr '\n' ' ' < "$RAW/.err" | cut -c1-300)"
    jq -cn --arg e "$err" '{error:$e}' > "$RAW/$name.json"; rm -f "$RAW/$name.json.tmp"
  fi
  rm -f "$RAW/.err"
}

# ---- 1. versions and discovery ----------------------------------------------------------------
if [ -z "$FIX" ]; then
  k version -o json > "$RAW/version.full" 2>/dev/null || true
  jq -e '.serverVersion.gitVersion' "$RAW/version.full" >/dev/null 2>&1 || { echo "cannot reach the API server for context '$CTX'" >&2; exit 3; }
  jq -c '{server: .serverVersion.gitVersion, client: .clientVersion.gitVersion}' "$RAW/version.full" > "$RAW/version.json"
  rm -f "$RAW/version.full"
  k api-versions 2>/dev/null | jq -R . | jq -cs . > "$RAW/api-versions.json" || echo '{"error":"api-versions failed"}' > "$RAW/api-versions.json"
else
  collect version .
  collect api-versions .
fi
jq -e '.server' "$RAW/version.json" >/dev/null 2>&1 || { echo "no server version recorded" >&2; exit 3; }

# ---- 2. inventory (trimmed at source) ---------------------------------------------------------
POOL='(.metadata.labels["eks.amazonaws.com/nodegroup"] // .metadata.labels["cloud.google.com/gke-nodepool"] // .metadata.labels["kubernetes.azure.com/agentpool"] // .metadata.labels["karpenter.sh/nodepool"] // .metadata.labels["eks.amazonaws.com/compute-type"] // "")'
collect nodes "[.items[] | {name: .metadata.name, kubelet: .status.nodeInfo.kubeletVersion, provider_id: (.spec.providerID // \"\"), pool: $POOL, labels: (.metadata.labels // {}), unschedulable: (.spec.unschedulable // false), ready: ([.status.conditions[]? | select(.type==\"Ready\") | .status][0] // \"Unknown\")}]" get nodes
# --pool-label: the pool is that label's value. Applied to the recorded node labels, so it works in fixture mode
# too; fixtures recorded before labels were captured can't be regrouped, which is said out loud.
if [ -n "$PLABEL" ]; then
  if jq -e 'type == "array" and any(.[]; has("labels"))' "$RAW/nodes.json" >/dev/null 2>&1; then
    jq -c --arg l "$PLABEL" 'map(.pool = (.labels[$l] // ""))' "$RAW/nodes.json" > "$RAW/nodes.json.tmp" && mv "$RAW/nodes.json.tmp" "$RAW/nodes.json"
  else
    echo "note: the recorded nodes carry no labels, so --pool-label $PLABEL could not be applied; pools keep their recorded names" >&2
    PLABEL_SKIPPED=1
  fi
fi
WL='[.items[] | {ns: .metadata.namespace, name: .metadata.name, replicas: (.spec.replicas // 1), ready: (.status.readyReplicas // 0), images: [.spec.template.spec.containers[].image]}]'
collect deployments "$WL" get deployments -A
collect statefulsets "$WL" get statefulsets -A
collect daemonsets '[.items[] | {ns: .metadata.namespace, name: .metadata.name, desired: (.status.desiredNumberScheduled // 0), ready: (.status.numberReady // 0), images: [.spec.template.spec.containers[].image]}]' get daemonsets -A
collect pods '[.items[] | {ns: .metadata.namespace, name: .metadata.name, node: (.spec.nodeName // ""), phase: .status.phase,
  owner: ([.metadata.ownerReferences[]? | select(.controller == true) | {kind, name}][0] // null),
  mirror: ((.metadata.annotations // {}) | has("kubernetes.io/config.mirror")),
  empty_dir: [.spec.volumes[]? | select(.emptyDir) | .name], host_path: [.spec.volumes[]? | select(.hostPath) | .name],
  claims: [.spec.volumes[]? | select(.persistentVolumeClaim) | .persistentVolumeClaim.claimName]}]' get pods -A
collect pdbs '[.items[] | {ns: .metadata.namespace, name: .metadata.name, min_available: .spec.minAvailable, max_unavailable: .spec.maxUnavailable,
  owner: ([.metadata.ownerReferences[]? | select(.controller == true) | {kind, name, api_version: .apiVersion}][0] // null),
  expected: (.status.expectedPods // 0), healthy: (.status.currentHealthy // 0), disruptions_allowed: (.status.disruptionsAllowed // 0)}]' get poddisruptionbudgets -A
# Storage: only names, the bound volume and the zones a PV is pinned to (node affinity or legacy zone labels).
collect pvcs '[.items[] | {ns: .metadata.namespace, name: .metadata.name, volume: (.spec.volumeName // "")}]' get persistentvolumeclaims -A
ZK='(. == "topology.kubernetes.io/zone" or . == "failure-domain.beta.kubernetes.io/zone")'
collect pvs "[.items[] | {name: .metadata.name, zones: ([.spec.nodeAffinity.required.nodeSelectorTerms[]?.matchExpressions[]? | select(.key | $ZK) | select(.operator == \"In\") | .values[]]
  + [(.metadata.labels // {}) | to_entries[] | select(.key | $ZK) | .value | split(\"__\")[]] | unique)}]" get persistentvolumes
WH='[.items[] | {name: .metadata.name, webhooks: [.webhooks[]? | {name, failure_policy: (.failurePolicy // "Fail"), service: (.clientConfig.service // null), url: (.clientConfig.url // null)}]}]'
collect validating-webhooks "$WH" get validatingwebhookconfigurations
collect mutating-webhooks "$WH" get mutatingwebhookconfigurations
collect services '[.items[] | {ns: .metadata.namespace, name: .metadata.name}]' get services -A
collect endpointslices '[.items[] | {ns: .metadata.namespace, service: (.metadata.labels["kubernetes.io/service-name"] // ""), ready: ([.endpoints[]? | select(.conditions.ready != false)] | length)}]' get endpointslices -A
collect apiservices '[.items[] | {name: .metadata.name, service: (.spec.service // null), available: ([.status.conditions[]? | select(.type=="Available") | .status][0] // "Unknown"), reason: ([.status.conditions[]? | select(.type=="Available") | .reason][0] // "")}]' get apiservices

# ---- 3. removed APIs: objects last written through an API version the target no longer serves --
SMINOR="$(jq -r '.server | capture("^v?1\\.(?<m>[0-9]+)").m' "$RAW/version.json")"
jq -r --argjson c "$SMINOR" --argjson t "$TMINOR" \
  '.removed[] | select(.removed_in > $c and .removed_in <= $t) | (.list_as // "\(.resource).\(.group)")' "$REMOVED" | sort -u > "$RAW/.window"
OBJ='[.items[] | {ns: (.metadata.namespace // ""), name: .metadata.name, last_applied: ((.metadata.annotations // {})["kubectl.kubernetes.io/last-applied-configuration"] // "" | (try (fromjson | .apiVersion) catch "")), writers: [.metadata.managedFields[]? | {manager, api_version: .apiVersion}]}]'
while IFS= read -r res; do
  [ -n "$res" ] || continue
  collect "objects-$res" "$OBJ" get "$res" -A --show-managed-fields
done < "$RAW/.window"

# ---- 4. apiserver_requested_deprecated_apis (requests since each apiserver instance started) ---
if [ -z "$FIX" ]; then
  if k get --raw /metrics 2>/dev/null > "$RAW/.metrics"; then
    { grep '^apiserver_requested_deprecated_apis{' "$RAW/.metrics" || true; } | jq -R '[scan("(\\w+)=\"([^\"]*)\"") | {(.[0]): .[1]}] | add' | jq -cs . > "$RAW/deprecated-metric.json"
  else
    echo '{"error":"GET /metrics not permitted or not exposed by this provider"}' > "$RAW/deprecated-metric.json"
  fi
  rm -f "$RAW/.metrics"
else
  collect deprecated-metric .
fi

# ---- 5. optional scanners. kubent runs with --helm3=false so Helm release Secrets are not read. ----
if [ -z "$FIX" ] && [ "$TOOLS" = 1 ]; then
  if command -v kubent >/dev/null 2>&1; then
    printf 'kubent --context %s --helm3=false -t %s.0 -o json\n' "$CTX" "$TARGET" >> "$RAW/calls.log"
    kubent --context "$CTX" --helm3=false -t "$TARGET.0" -o json > "$RAW/kubent.json" 2>/dev/null || echo '{"error":"kubent failed"}' > "$RAW/kubent.json"
  fi
  if [ "$PLUTO" = 1 ] && command -v pluto >/dev/null 2>&1; then
    printf 'pluto detect-api-resources --kube-context %s --target-versions k8s=v%s.0 -o json\n' "$CTX" "$TARGET" >> "$RAW/calls.log"
    pluto detect-api-resources --kube-context "$CTX" --target-versions "k8s=v$TARGET.0" -o json > "$RAW/pluto.json" 2>/dev/null || true
    [ -s "$RAW/pluto.json" ] || echo '{"items":[]}' > "$RAW/pluto.json"
  fi
elif [ -n "$FIX" ]; then
  [ -f "$FIX/kubent.json" ] && cp "$FIX/kubent.json" "$RAW/kubent.json"
  [ -f "$FIX/pluto.json" ] && cp "$FIX/pluto.json" "$RAW/pluto.json"
fi

# ---- 6. analyse and report ---------------------------------------------------------------------
objs='{}'
while IFS= read -r res; do
  [ -n "$res" ] || continue
  objs="$(jq -c --arg r "$res" --slurpfile o "$RAW/objects-$res.json" '. + {($r): $o[0]}' <<<"$objs")"
done < "$RAW/.window"
rm -f "$RAW/.window"
opt() { if [ -f "$RAW/$1.json" ]; then cat "$RAW/$1.json"; else echo null; fi; }

jq -n --arg ctx "$CTX" --argjson target "$TMINOR" --arg now "$NOW" --argjson traffic_ok "$TRAFFIC_OK" --arg pool_label "$PLABEL" --argjson pool_label_skipped "$PLABEL_SKIPPED" --slurpfile support "$SUPPORT" \
  --slurpfile version "$RAW/version.json" --slurpfile apiversions "$RAW/api-versions.json" \
  --slurpfile nodes "$RAW/nodes.json" --slurpfile deployments "$RAW/deployments.json" \
  --slurpfile statefulsets "$RAW/statefulsets.json" --slurpfile daemonsets "$RAW/daemonsets.json" \
  --slurpfile pods "$RAW/pods.json" --slurpfile pdbs "$RAW/pdbs.json" \
  --slurpfile pvcs "$RAW/pvcs.json" --slurpfile pvs "$RAW/pvs.json" \
  --slurpfile vwh "$RAW/validating-webhooks.json" --slurpfile mwh "$RAW/mutating-webhooks.json" \
  --slurpfile services "$RAW/services.json" --slurpfile slices "$RAW/endpointslices.json" \
  --slurpfile apiservices "$RAW/apiservices.json" --slurpfile metric "$RAW/deprecated-metric.json" \
  --slurpfile removed "$REMOVED" --argjson objects "$objs" \
  --argjson kubent "$(opt kubent)" --argjson pluto "$(opt pluto)" \
  '{ctx: $ctx, target: $target, now: $now, version: $version[0], apiversions: $apiversions[0], nodes: $nodes[0],
    deployments: $deployments[0], statefulsets: $statefulsets[0], daemonsets: $daemonsets[0], pods: $pods[0], pdbs: $pdbs[0], pvcs: $pvcs[0], pvs: $pvs[0],
    vwh: $vwh[0], mwh: $mwh[0], services: $services[0], slices: $slices[0], apiservices: $apiservices[0],
    metric: $metric[0], removed: $removed[0].removed, objects: $objects, kubent: $kubent, pluto: $pluto,
    support: $support[0], traffic_ok: $traffic_ok, pool_label: $pool_label, pool_label_skipped: ($pool_label_skipped == 1)}' > "$RAW/bundle.json"

jq -f "$HERE/preflight-analyze.jq" "$RAW/bundle.json" > "$OUT/preflight.json"
rm -f "$RAW/bundle.json"
jq -r -f "$HERE/preflight-report.jq" "$OUT/preflight.json" | tee "$OUT/preflight.txt"
echo "JSON: $OUT/preflight.json  Report: $OUT/preflight.txt  Raw (trimmed) inputs: $RAW/"
[ "$(jq -r .verdict "$OUT/preflight.json")" != "NO-GO" ]
