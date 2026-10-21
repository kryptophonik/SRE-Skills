#!/usr/bin/env bash
# Post-step verification for an upgrade: run after the control plane, after each node pool and after add-ons.
# Its kubectl calls are get / version only (same restricted kubectl wrapper as upgrade-preflight.sh; other verbs exit 2).
#
# Usage: bash scripts/verify-step.sh --context <ctx> [--expect-control-plane 1.xx] [--expect-nodes 1.xx [--expect-pool <pool>]]
#                                   [--pool-label <node-label-key>] [--out <dir>]
#        bash scripts/verify-step.sh --context <name> --fixtures <dir> [same expectations]
# --pool-label: node label whose value names the pool, for clusters without EKS/GKE/AKS/Karpenter pool labels
#   (kind, kubeadm); also applied in fixture mode. Default output: a new ${TMPDIR:-/tmp}/k8sup-verify-<context>-<UTC ts>.XXXXXX
# Checks: control-plane minor, every node Ready and schedulable, node-pool kubelet minor, kube-system
# Deployments/DaemonSets fully ready, aggregated APIServices Available, no Pending/Failed/crash-looping pods.
# Exit: 0 PASS, 1 FAIL (stop the upgrade), 2 usage error or refused, 3 cluster unreachable.
#

set -euo pipefail

CTX="" CP="" POOL="" NODES="" OUT="" FIX="" PLABEL="" TIMEOUT="${PREFLIGHT_TIMEOUT:-30s}"
usage() { sed -n '5,12p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }
while [ $# -gt 0 ]; do
  case "$1" in
    --context) CTX="${2:-}"; shift 2 ;;
    --expect-control-plane) CP="${2:-}"; shift 2 ;;
    --expect-pool) POOL="${2:-}"; shift 2 ;;
    --expect-nodes) NODES="${2:-}"; shift 2 ;;
    --pool-label) PLABEL="${2:-}"; shift 2 ;;
    --out) OUT="${2:-}"; shift 2 ;;
    --fixtures) FIX="${2:-}"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "unknown argument: $1" >&2; usage ;;
  esac
done
[ -n "$CTX" ] || { echo "refusing: --context <ctx> is required; the current kubeconfig context is never assumed" >&2; exit 2; }
for v in "$CP" "$NODES"; do
  [ -z "$v" ] || [[ "$v" =~ ^v?1\.[0-9]+$ ]] || { echo "refusing: versions must look like 1.32" >&2; exit 2; }
done
{ [ -z "$POOL" ] || [ -n "$NODES" ]; } || { echo "refusing: --expect-pool needs --expect-nodes" >&2; exit 2; }
[ -z "$PLABEL" ] || [[ "$PLABEL" =~ ^[A-Za-z0-9][A-Za-z0-9._/-]*$ ]] || { echo "refusing: --pool-label must be a node label key such as node.example.com/pool" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; exit 2; }
CP="${CP#v}"; NODES="${NODES#v}"
# Validate everything before creating any directory: a refused run leaves nothing behind.
if [ -n "$FIX" ]; then
  [ -d "$FIX" ] || { echo "fixtures dir not found: $FIX" >&2; exit 2; }
else
  command -v kubectl >/dev/null 2>&1 || { echo "kubectl is required" >&2; exit 2; }
  kubectl config get-contexts "$CTX" >/dev/null 2>&1 || { echo "refusing: context '$CTX' is not in the kubeconfig" >&2; exit 2; }
fi
# Default output: mktemp -d adds a random suffix, so two runs in the same second never share a directory.
if [ -z "$OUT" ]; then
  OUT="$(umask 077; mktemp -d "${TMPDIR:-/tmp}/k8sup-verify-${CTX//[^A-Za-z0-9_.-]/_}-$(date -u +%Y%m%dT%H%M%SZ).XXXXXX")" || { echo "cannot create an output directory under ${TMPDIR:-/tmp}" >&2; exit 2; }
fi
RAW="$OUT/raw"; ( umask 077; mkdir -p "$RAW" )
[ -n "$FIX" ] || : > "$RAW/calls.log"

k() {
  case "$1" in
    get|version) ;;
    *) echo "refusing non-read kubectl verb: $1" >&2; exit 2 ;;
  esac
  printf '%s\n' "$*" >> "$RAW/calls.log"
  kubectl --context "$CTX" --request-timeout="$TIMEOUT" "$@"
}
collect() {
  local name="$1" filter="$2"; shift 2
  if [ -n "$FIX" ]; then
    if [ -f "$FIX/$name.json" ]; then cp "$FIX/$name.json" "$RAW/$name.json"; else printf '{"error":"not recorded"}\n' > "$RAW/$name.json"; fi
    return 0
  fi
  k "$@" -o json 2>/dev/null | jq -c "$filter" > "$RAW/$name.json" 2>/dev/null || printf '{"error":"%s failed"}\n' "$name" > "$RAW/$name.json"
}

if [ -z "$FIX" ]; then
  k version -o json > "$RAW/version.full" 2>/dev/null || true
  jq -e '.serverVersion.gitVersion' "$RAW/version.full" >/dev/null 2>&1 || { echo "cannot reach the API server for context '$CTX'" >&2; exit 3; }
  jq -c '{server: .serverVersion.gitVersion}' "$RAW/version.full" > "$RAW/version.json"; rm -f "$RAW/version.full"
else
  collect version .
fi
if [ -n "$PLABEL" ]; then POOLX="(.metadata.labels[\"$PLABEL\"] // \"\")"; else
POOLX='(.metadata.labels["eks.amazonaws.com/nodegroup"] // .metadata.labels["cloud.google.com/gke-nodepool"] // .metadata.labels["kubernetes.azure.com/agentpool"] // .metadata.labels["karpenter.sh/nodepool"] // "")'; fi
collect nodes "[.items[] | {name: .metadata.name, kubelet: .status.nodeInfo.kubeletVersion, pool: $POOLX, labels: (.metadata.labels // {}), unschedulable: (.spec.unschedulable // false), ready: ([.status.conditions[]? | select(.type==\"Ready\") | .status][0] // \"Unknown\")}]" get nodes
# --pool-label: the pool is that label's value. Applied to the recorded node labels, so it works in fixture mode
# too; fixtures recorded before labels were captured can't be regrouped, which is said out loud.
if [ -n "$PLABEL" ]; then
  if jq -e 'type == "array" and any(.[]; has("labels"))' "$RAW/nodes.json" >/dev/null 2>&1; then
    jq -c --arg l "$PLABEL" 'map(.pool = (.labels[$l] // ""))' "$RAW/nodes.json" > "$RAW/nodes.json.tmp" && mv "$RAW/nodes.json.tmp" "$RAW/nodes.json"
  else
    echo "note: the recorded nodes carry no labels, so --pool-label $PLABEL could not be applied; pools keep their recorded names" >&2
  fi
fi
collect ks-deployments '[.items[] | {name: .metadata.name, want: (.spec.replicas // 1), ready: (.status.readyReplicas // 0)}]' get deployments -n kube-system
collect ks-daemonsets '[.items[] | {name: .metadata.name, want: (.status.desiredNumberScheduled // 0), ready: (.status.numberReady // 0)}]' get daemonsets -n kube-system
collect apiservices '[.items[] | select(.spec.service != null) | {name: .metadata.name, available: ([.status.conditions[]? | select(.type=="Available") | .status][0] // "Unknown")}]' get apiservices
collect bad-pods '[.items[] | select((.status.phase | IN("Running", "Succeeded") | not) or any(.status.containerStatuses[]?; .state.waiting.reason // "" | test("CrashLoopBackOff|ImagePullBackOff|ErrImagePull|CreateContainerConfigError"))) | {ns: .metadata.namespace, name: .metadata.name, phase: .status.phase, reason: ([.status.containerStatuses[]?.state.waiting.reason // empty][0] // .status.reason // "")}]' get pods -A

jq -n --arg cp "$CP" --arg pool "$POOL" --arg nodes "$NODES" --arg ctx "$CTX" \
  --slurpfile v "$RAW/version.json" --slurpfile n "$RAW/nodes.json" --slurpfile d "$RAW/ks-deployments.json" \
  --slurpfile ds "$RAW/ks-daemonsets.json" --slurpfile a "$RAW/apiservices.json" --slurpfile p "$RAW/bad-pods.json" '
  def minor: (capture("^v?1\\.(?<m>[0-9]+)") // {m: "-1"}) | .m | tonumber;
  def arr(x; what): if (x | type) == "array" then x else error("could not read \(what)") end;
  def chk(name; pass; detail): {check: name, result: (if pass then "PASS" else "FAIL" end), detail: detail};
  [ (if $cp != "" then chk("control-plane version"; ($v[0].server | minor) == ($cp | minor); "server \($v[0].server), expected 1.\($cp | minor)") else empty end),
    ( try (arr($n[0]; "nodes") as $nl
        | chk("nodes Ready"; all($nl[]; .ready == "True"); ([$nl[] | select(.ready != "True") | .name] | if length == 0 then "all \($nl | length) Ready" else "not Ready: " + join(", ") end)),
          chk("nodes schedulable"; all($nl[]; .unschedulable | not); ([$nl[] | select(.unschedulable) | .name] | if length == 0 then "none cordoned" else "cordoned: " + join(", ") end)),
          (if $nodes != "" and $pool != "" then [$nl[] | select(.pool == $pool)] as $pn
            | chk("pool \($pool) at \($nodes)"; ($pn | length) > 0 and all($pn[]; (.kubelet | minor) == ($nodes | minor)); ([$pn[] | select((.kubelet | minor) != ($nodes | minor)) | "\(.name)=\(.kubelet)"] | if ($pn | length) == 0 then "no nodes found with that pool label" elif length == 0 then "all \($pn | length) nodes match" else "behind: " + join(", ") end))
           elif $nodes != "" then
             chk("all nodes at \($nodes)"; ($nl | length) > 0 and all($nl[]; (.kubelet | minor) == ($nodes | minor)); ([$nl[] | select((.kubelet | minor) != ($nodes | minor)) | "\(.name)=\(.kubelet)"] | if ($nl | length) == 0 then "no nodes found" elif length == 0 then "all \($nl | length) nodes match" else "behind: " + join(", ") end))
           else empty end))
      catch chk("nodes readable"; false; .) ),
    ( try (arr($d[0]; "kube-system deployments") | chk("kube-system Deployments ready"; all(.[]; .ready >= .want); ([.[] | select(.ready < .want) | "\(.name) \(.ready)/\(.want)"] | if length == 0 then "all ready" else join(", ") end))) catch chk("kube-system Deployments readable"; false; .) ),
    ( try (arr($ds[0]; "kube-system daemonsets") | chk("kube-system DaemonSets ready"; all(.[]; .ready >= .want); ([.[] | select(.ready < .want) | "\(.name) \(.ready)/\(.want)"] | if length == 0 then "all ready" else join(", ") end))) catch chk("kube-system DaemonSets readable"; false; .) ),
    ( try (arr($a[0]; "apiservices") | chk("aggregated APIs Available"; all(.[]; .available == "True"); ([.[] | select(.available != "True") | .name] | if length == 0 then "all Available" else "unavailable: " + join(", ") end))) catch chk("apiservices readable"; false; .) ),
    ( try (arr($p[0]; "pods") | chk("no Pending/Failed/crash-looping pods"; length == 0; (if length == 0 then "none" else ([.[:20][] | "\(.ns)/\(.name) \(.phase) \(.reason)"] | join("; ")) end))) catch chk("pods readable"; false; .) )
  ] as $checks
  | {context: $ctx, server_version: $v[0].server, result: (if any($checks[]; .result == "FAIL") then "FAIL" else "PASS" end), checks: $checks}' > "$OUT/verify.json"

jq -r '"Upgrade step verification: context \(.context), server \(.server_version): \(.result)", (.checks[] | "  \(.result)  \(.check): \(.detail)")' "$OUT/verify.json"
echo "JSON: $OUT/verify.json"
[ "$(jq -r .result "$OUT/verify.json")" = PASS ]
