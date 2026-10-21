#!/usr/bin/env bash
# Tests for scripts/upgrade-preflight.sh. Runs on bash 3.2 and bash 5.
#   bash tests/run-tests.sh                 offline: argument checks, static kubectl-verb checks, recorded fixtures
#   bash tests/run-tests.sh --kind          also: throwaway kind cluster with audit logging (needs docker or podman, kind, kubectl)
#   bash tests/run-tests.sh --kind --keep   leave the kind cluster running afterwards
#   bash tests/run-tests.sh --kind --record <dir>   also copy the live run's trimmed inputs to <dir> (to refresh fixtures)
# The kind cluster is created, seeded and deleted by this script. It never touches any other context.

# shellcheck disable=SC2034  # results are read inside the '...' strings that check() evaluates
set -u
cd "$(dirname "$0")/.." || exit 2
SKILL="$(pwd)"
SH="${BASH:-bash}"
KIND=0 KEEP=0 RECORD=""
while [ $# -gt 0 ]; do
  case "$1" in
    --kind) KIND=1; shift ;;
    --keep) KEEP=1; shift ;;
    --record) RECORD="${2:-}"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
TMP="$(mktemp -d "${TMPDIR:-/tmp}/k8sup-tests.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
PASS=0 FAIL=0
# Support-status findings depend on today's date; pin it so the suite gives the same answer every day.
export PREFLIGHT_NOW="2026-10-18T12:00:00Z"
# Fingerprint of the skill tree: the suite must leave it exactly as it found it.
tree_sum() { { find . -print | LC_ALL=C sort; find . -type f -exec cksum {} + | LC_ALL=C sort; } | cksum; }
TREE_BEFORE="$(tree_sum)"
ok() { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
no() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n' "$1"; }
check() { if eval "$2"; then ok "$1"; else no "$1"; fi; }
# has <json> <severity> <category> <object-substring>
has() { jq -e --arg s "$2" --arg c "$3" --arg o "$4" 'any(.findings[]; .severity == $s and .category == $c and (.object | contains($o)))' "$1" >/dev/null; }
hasnt() { ! jq -e --arg c "$2" --arg o "$3" 'any(.findings[]; .category == $c and (.object | contains($o)))' "$1" >/dev/null; }
verdict() { jq -r .verdict "$1"; }
pf() { "$SH" scripts/upgrade-preflight.sh "$@" >"$TMP/last.out" 2>&1; }

echo "# bash: $SH ($("$SH" -c 'echo $BASH_VERSION'))"

# ---- arguments and refusals ----------------------------------------------------------------
pf --target 1.32 --fixtures tests/fixtures/kind-1.31; check "missing --context is refused (exit 2)" '[ $? -eq 2 ]'
grep -q 'refusing: --context' "$TMP/last.out"; check "refusal names the missing --context" '[ $? -eq 0 ]'
pf --context x --target 132 --fixtures tests/fixtures/kind-1.31; check "malformed --target is refused (exit 2)" '[ $? -eq 2 ]'
pf --context x --target 1.32 --fixtures "$TMP/nope"; check "missing fixtures dir is refused (exit 2)" '[ $? -eq 2 ]'
if command -v kubectl >/dev/null 2>&1; then
  KUBECONFIG="$TMP/empty-kubeconfig" pf --context does-not-exist --target 1.32 --out "$TMP/x"
  check "unknown context is refused before any API call (exit 2)" '[ $? -eq 2 ]'
fi
# Refused runs create nothing: not in the working directory, not under TMPDIR.
mkdir -p "$TMP/refuse-cwd" "$TMP/refuse-tmp"
( cd "$TMP/refuse-cwd" && export TMPDIR="$TMP/refuse-tmp" KUBECONFIG="$TMP/empty-kubeconfig"
  "$SH" "$SKILL/scripts/upgrade-preflight.sh" --target 1.32 --fixtures "$SKILL/tests/fixtures/kind-1.31"
  "$SH" "$SKILL/scripts/upgrade-preflight.sh" --context x --target 132 --fixtures "$SKILL/tests/fixtures/kind-1.31"
  "$SH" "$SKILL/scripts/upgrade-preflight.sh" --context x --target 1.32 --fixtures "$TMP/nope"
  "$SH" "$SKILL/scripts/upgrade-preflight.sh" --context does-not-exist --target 1.32
  "$SH" "$SKILL/scripts/verify-step.sh" --context x --expect-nodes 132 --fixtures "$SKILL/tests/fixtures/verify-after-pool"
  "$SH" "$SKILL/scripts/verify-step.sh" --context x --fixtures "$TMP/nope" ) >/dev/null 2>&1
check "refused runs create no directory in the cwd or under TMPDIR" '[ -z "$(ls -A "$TMP/refuse-cwd" "$TMP/refuse-tmp" | grep -v ":$" | grep -v "^$")" ]'
# Default output goes under TMPDIR (outside the repo), never into the working directory.
mkdir -p "$TMP/def-cwd" "$TMP/def-tmp"
( cd "$TMP/def-cwd" && TMPDIR="$TMP/def-tmp" "$SH" "$SKILL/scripts/upgrade-preflight.sh" --context kind-x --target 1.32 --fixtures "$SKILL/tests/fixtures/kind-1.31"
  TMPDIR="$TMP/def-tmp" "$SH" "$SKILL/scripts/verify-step.sh" --context kind-x --fixtures "$SKILL/tests/fixtures/verify-after-pool" ) >/dev/null 2>&1
check "default preflight output is \$TMPDIR/k8sup-<ctx>-<target>-<timestamp>" '[ -s "$(ls -d "$TMP"/def-tmp/k8sup-kind-x-1.32-*Z.* 2>/dev/null | head -n 1)/preflight.json" ]'
check "default verify output is \$TMPDIR/k8sup-verify-<ctx>-<timestamp>" '[ -s "$(ls -d "$TMP"/def-tmp/k8sup-verify-kind-x-*Z.* 2>/dev/null | head -n 1)/verify.json" ]'
check "nothing is written to the working directory by default" '[ -z "$(ls -A "$TMP/def-cwd")" ]'

# ---- static: the only kubectl verbs the script can issue are reads ----------------------------
for S in scripts/upgrade-preflight.sh scripts/verify-step.sh; do
  bad="$(grep -nE '(^|[^A-Za-z_-])k (apply|create|delete|patch|replace|edit|scale|drain|cordon|uncordon|taint|label|annotate|rollout|exec|cp|run|set|debug|port-forward|attach|proxy)\b' "$S" || true)"
  check "$(basename "$S"): no k <write-verb> calls in the script" '[ -z "$bad" ]'
  verbs="$(grep -oE '(collect [a-z$"{}-]+ ("[^"]*"|'"'"'[^'"'"']*'"'"'|\$[A-Z]+|\.) |(^|[ (!])k )[a-z-]+' "$S" | awk '{print $NF}' | sort -u | tr '\n' ' ')"
  check "$(basename "$S"): every kubectl call is get/version/api-versions (found: $verbs)" '[ -z "$(printf "%s\n" $verbs | grep -vxE "get|version|api-versions")" ]'
  direct="$(grep -nE '(^|[^-A-Za-z])kubectl ' "$S" | grep -vE '^[0-9]+:#|echo "|command -v kubectl|kubectl config get-contexts "\$CTX"|kubectl --context "\$CTX" --request-timeout' || true)"
  check "$(basename "$S"): kubectl is only called through the restricted wrapper" '[ -z "$direct" ]'
done
S=scripts/upgrade-preflight.sh
# Exercise the wrapper itself against a stub kubectl that records whether it was reached.
mkdir -p "$TMP/stub"; printf '#!/bin/sh\necho "$*" >> "%s/stub/called"\n' "$TMP" > "$TMP/stub/kubectl"; chmod +x "$TMP/stub/kubectl"
sed -n '/^k() {/,/^}/p' "$S" > "$TMP/k.sh"
for v in delete apply patch drain cordon scale exec; do
  ( PATH="$TMP/stub:$PATH" RAW="$TMP" CTX=x TIMEOUT=1s; . "$TMP/k.sh"; k "$v" pods x ) >/dev/null 2>&1
  rcw=$?
  check "wrapper refuses '$v' (exit 2) without reaching kubectl" '[ $rcw -eq 2 ] && [ ! -f "$TMP/stub/called" ]'
done
( PATH="$TMP/stub:$PATH" RAW="$TMP" CTX=x TIMEOUT=1s; . "$TMP/k.sh"; k get nodes ) >/dev/null 2>&1
check "wrapper passes 'get' through with --context" 'grep -q -- "--context x --request-timeout=1s get nodes" "$TMP/stub/called"'
check "script never reads secrets or configmaps" '! grep -nE "get +(secrets?|configmaps?)\b" "$S" >/dev/null'

# ---- recorded fixtures: live kind 1.31 cluster (seeded) -> 1.32 -------------------------------
pf --context kind-k8sup-test --target 1.32 --fixtures tests/fixtures/kind-1.31 --out "$TMP/kind"; rc=$?
J="$TMP/kind/preflight.json"
check "kind fixture: NO-GO exits 1" '[ $rc -eq 1 ] && [ "$(verdict "$J")" = NO-GO ]'
check "kind fixture: PDB maxUnavailable 0 is a blocker" 'has "$J" BLOCKER pdb upgrade-test/web-pdb'
check "kind fixture: PDB minAvailable = replicas is a blocker" 'has "$J" BLOCKER pdb upgrade-test/solo-pdb'
check "kind fixture: object written via removed API is a blocker" 'has "$J" BLOCKER removed-api FlowSchema/upgrade-test-legacy'
check "kind fixture: deprecated-API metric is folded into the FlowSchema blocker" 'jq -e "any(.findings[]; .object == \"FlowSchema/upgrade-test-legacy\" and (.sources | index(\"deprecated-API metric\")))" "$J" >/dev/null && hasnt "$J" removed-api "v1beta3 flowschemas"'
check "kind fixture: exactly 4 blockers (2 PDBs, FlowSchema, webhook) after dedupe" '[ "$(jq .summary.blockers "$J")" -eq 4 ]'
check "kind fixture: one removed-api finding per object" '[ "$(jq "[.findings[] | select(.category == \"removed-api\") | .object] | length" "$J")" -eq "$(jq "[.findings[] | select(.category == \"removed-api\") | .object] | unique | length" "$J")" ]'
check "kind fixture: no odd object names for cluster-scoped objects" '! jq -r ".findings[].object" "$J" | grep -qE "//|<undefined>"'
check "kind fixture: upstream EOL of 1.32 is a support warning with the hop path" 'has "$J" WARN support 1.32 && jq -e "any(.findings[]; .category == \"support\" and (.message | contains(\"2026-02-28\") and contains(\"1.33 -> 1.34 -> 1.35\")))" "$J" >/dev/null'
check "kind fixture: Fail webhook with missing service is a blocker" 'has "$J" BLOCKER webhook upgrade-test-broken'
check "kind fixture: single-replica Deployment is a warning" 'has "$J" WARN single-replica deployment/upgrade-test/solo'
check "kind fixture: 2-replica Deployment is not flagged" 'hasnt "$J" single-replica deployment/upgrade-test/web'
check "kind fixture: bare pod is a warning" 'has "$J" WARN bare-pod pod/upgrade-test/bare'
check "kind fixture: emptyDir pod is a warning" 'has "$J" WARN local-storage pod/upgrade-test/bare'
check "kind fixture: DaemonSet pods are not flagged as local storage" 'hasnt "$J" local-storage kube-proxy'
check "kind fixture: CoreDNS at the version kubeadm ships for 1.32 is INFO, not WARN" 'has "$J" INFO addon deployment/kube-system/coredns && ! has "$J" WARN addon deployment/kube-system/coredns'
check "kind fixture: control plane step is OK" 'has "$J" OK skew "control plane"'
check "kind fixture: report and JSON written" '[ -s "$TMP/kind/preflight.txt" ] && jq -e .summary "$J" >/dev/null'
if [ -f tests/fixtures/kind-1.31/kubent.json ]; then
  check "kind fixture: kubent finding merged into the object finding" 'jq -e "any(.findings[]; .object == \"FlowSchema/upgrade-test-legacy\" and (.sources | index(\"kubent\")))" "$J" >/dev/null'
fi
if [ -f tests/fixtures/kind-1.31/pluto.json ]; then
  check "kind fixture: pluto finding merged into the object finding" 'jq -e "any(.findings[]; .object == \"FlowSchema/upgrade-test-legacy\" and (.sources | index(\"pluto\")))" "$J" >/dev/null'
fi

# Same recording, other targets.
pf --context kind-k8sup-test --target 1.33 --fixtures tests/fixtures/kind-1.31 --out "$TMP/kind133"
check "skipping a minor (1.31 -> 1.33) is a blocker" 'has "$TMP/kind133/preflight.json" BLOCKER skew "control plane"'
pf --context kind-k8sup-test --target 1.31 --fixtures tests/fixtures/kind-1.31 --out "$TMP/kind131"
check "target equal to current is a blocker" 'has "$TMP/kind131/preflight.json" BLOCKER skew "control plane"'
check "no removed-API blocker when target <= current (tools' later removals are INFO)" '! has "$TMP/kind131/preflight.json" BLOCKER removed-api FlowSchema/upgrade-test-legacy'

# ---- synthetic EKS fixture: skew, add-ons, PDB 100%, webhook without endpoints ---------------
pf --context eks-prod --target 1.32 --fixtures tests/fixtures/eks-skew --out "$TMP/eks"; rc=$?
J="$TMP/eks/preflight.json"
check "eks fixture: provider detected as eks" '[ "$(jq -r .provider "$J")" = eks ]'
check "eks fixture: NO-GO exits 1" '[ $rc -eq 1 ]'
check "eks fixture: kubelet 4 minors behind target is a blocker" 'has "$J" BLOCKER skew node/ip-10-0-3-10'
check "eks fixture: kubelet behind control plane is a warning" 'has "$J" WARN skew node/ip-10-0-2-10'
check "eks fixture: kubelet matching control plane is not flagged" 'hasnt "$J" skew node/ip-10-0-1-10'
check "eks fixture: kube-proxy too old for target is a blocker" 'has "$J" BLOCKER skew daemonset/kube-system/kube-proxy'
check "eks fixture: cluster-autoscaler minor mismatch is a warning" 'has "$J" WARN addon cluster-autoscaler'
check "eks fixture: VPC CNI listed for compatibility check" 'jq -e "any(.addons[]; .addon == \"Amazon VPC CNI\")" "$J" >/dev/null'
check "eks fixture: PDB minAvailable 100% is a blocker" 'has "$J" BLOCKER pdb payments/api-pdb'
check "eks fixture: PDB with 0 disruptions allowed is a blocker" 'has "$J" BLOCKER pdb payments/worker-pdb'
check "eks fixture: healthy PDB is not flagged" 'hasnt "$J" pdb web/frontend-pdb'
check "eks fixture: Fail webhook with no ready endpoints is a blocker" 'has "$J" BLOCKER webhook policy-validator'
check "eks fixture: healthy Fail webhook is not flagged" 'hasnt "$J" webhook healthy-validator'
check "eks fixture: Ignore webhook with missing service is a warning" 'has "$J" WARN webhook optional-mutator'
check "eks fixture: unavailable APIService is a warning" 'has "$J" WARN apiservice v1beta1.metrics.k8s.io'
check "eks fixture: NotReady node is a blocker" 'has "$J" BLOCKER health node/ip-10-0-2-11'
check "eks fixture: pools grouped" '[ "$(jq ".cluster.node_pools | length" "$J")" -eq 3 ]'

# ---- synthetic AKS fixture: nothing blocking, metric forbidden, one inventory call failed ----
pf --context aks-stage --target 1.34 --fixtures tests/fixtures/aks-partial --out "$TMP/aks"; rc=$?
J="$TMP/aks/preflight.json"
check "aks fixture: provider detected as aks" '[ "$(jq -r .provider "$J")" = aks ]'
check "aks fixture: GO-WITH-WARNINGS exits 0" '[ $rc -eq 0 ] && [ "$(verdict "$J")" = GO-WITH-WARNINGS ]'
check "aks fixture: failed pods call becomes a coverage warning, not silence" 'has "$J" WARN coverage pods'
check "aks fixture: forbidden metric is reported as unavailable" 'has "$J" INFO removed-api apiserver_requested_deprecated_apis'
check "aks fixture: empty removed-API window is stated" 'jq -e ".removed_api_window == []" "$J" >/dev/null'

# ---- synthetic GKE fixture: clean cluster ------------------------------------------------------
pf --context gke-dev --target 1.36 --fixtures tests/fixtures/gke-clean --out "$TMP/gke"; rc=$?
J="$TMP/gke/preflight.json"
check "gke fixture: provider detected as gke" '[ "$(jq -r .provider "$J")" = gke ]'
check "gke fixture: clean cluster is GO and exits 0" '[ $rc -eq 0 ] && [ "$(verdict "$J")" = GO ]'

# ---- removed APIs: re-applied object (L1), kubent alone, cumulative metric ----------------------
pf --context kind-k8sup-test --target 1.32 --fixtures tests/fixtures/kind-reapplied-v1 --out "$TMP/reap"; rc=$?
J="$TMP/reap/preflight.json"
check "re-applied as v1: leftover v1beta3 managedFields entry is not a BLOCKER" '! has "$J" BLOCKER removed-api FlowSchema/upgrade-test-legacy'
check "re-applied as v1: stale managedFields entry is INFO and says it is harmless" 'has "$J" INFO removed-api FlowSchema/upgrade-test-legacy && jq -e "any(.findings[]; .object == \"FlowSchema/upgrade-test-legacy\" and (.message | contains(\"harmless\")))" "$J" >/dev/null'
check "re-applied as v1: cumulative metric still blocks and explains why" 'has "$J" BLOCKER removed-api "v1beta3 flowschemas" && jq -e "any(.findings[]; .object | contains(\"v1beta3 flowschemas\")) and any(.findings[]; (.message | contains(\"cumulative\")) and (.fix | contains(\"--deprecated-traffic-checked\")))" "$J" >/dev/null'
pf --context kind-k8sup-test --target 1.32 --fixtures tests/fixtures/kind-reapplied-v1 --deprecated-traffic-checked --out "$TMP/reap2"
J="$TMP/reap2/preflight.json"
check "--deprecated-traffic-checked turns the cumulative metric into a WARN" 'has "$J" WARN removed-api "v1beta3 flowschemas" && [ "$(jq "[.findings[] | select(.category == \"removed-api\" and .severity == \"BLOCKER\")] | length" "$J")" -eq 0 ]'
check "--deprecated-traffic-checked leaves other blockers alone" 'has "$J" BLOCKER pdb upgrade-test/web-pdb'
# kubent alone (no object check hit, no pluto): removed by the target means BLOCKER.
cp -R tests/fixtures/kind-reapplied-v1 "$TMP/kubent-only" && cp tests/fixtures/kind-1.31/kubent.json "$TMP/kubent-only/"
echo '[]' > "$TMP/kubent-only/deprecated-metric.json"
pf --context k --target 1.32 --fixtures "$TMP/kubent-only" --out "$TMP/ko"
check "kubent: API removed by the target is a BLOCKER, cluster-scoped name has no namespace" 'has "$TMP/ko/preflight.json" BLOCKER removed-api FlowSchema/upgrade-test-legacy'

# ---- support status from references/support-status.json --------------------------------------
J="$TMP/eks/preflight.json"
check "support: EKS 1.32 target is in extended support, charges continue, hops named" 'has "$J" WARN support "EKS 1.32" && jq -e "any(.findings[]; .object == \"EKS 1.32\" and (.message | contains(\"0.6\") and contains(\"1.33 -> 1.34\")))" "$J" >/dev/null'
check "support: GKE 1.36 target has no support warning" 'hasnt "$TMP/gke/preflight.json" support 1.36'
check "support: AKS 1.34 target with community support ending within 30 days warns with the date" 'jq -e "any(.findings[]; .object == \"AKS 1.34\" and .severity == \"WARN\" and (.message | contains(\"2026-11\") and contains(\"within 30 days\")))" "$TMP/aks/preflight.json" >/dev/null'
PREFLIGHT_NOW="2026-12-15T00:00:00Z" pf --context aks-stage --target 1.34 --fixtures tests/fixtures/aks-partial --out "$TMP/aks-late"
check "support: AKS after community EOL warns that only LTS keeps it and it may not be offered" 'jq -e "any(.findings[]; .object == \"AKS 1.34\" and .severity == \"WARN\" and (.message | contains(\"LTS\") and contains(\"may not offer\")))" "$TMP/aks-late/preflight.json" >/dev/null'
PREFLIGHT_NOW="2028-01-15T00:00:00Z" pf --context gke-dev --target 1.37 --fixtures tests/fixtures/gke-clean --out "$TMP/gke-late"
check "support: quarter-only GKE dates count as past once the quarter ends" 'has "$TMP/gke-late/preflight.json" WARN support "GKE 1.37"'
# N3: hop advice skips minors whose support ends within 30 days (1.34 upstream EOL is 2026-10-27).
check "support: hop path skips 1.34 (upstream EOL within 30 days) and ends at 1.35" 'jq -e "any(.findings[]; .object == \"1.32\" and (.message | contains(\"more than 30 days\") and contains(\"is 1.35\")))" "$TMP/kind/preflight.json" >/dev/null'
check "support: EKS hop path stops at 1.34 (standard support ends 2026-12-02, beyond 30 days)" 'jq -e "any(.findings[]; .object == \"EKS 1.32\" and (.message | contains(\"path: 1.33 -> 1.34,\")))" "$TMP/eks/preflight.json" >/dev/null'
# Price notes carry the checked date and the official pricing page, so they never read as a quote.
check "support: EKS price WARN names checked 2026-10-18 and the EKS pricing page" 'jq -e "any(.findings[]; .object == \"EKS 1.32\" and (.message | contains(\"checked 2026-10-18\") and contains(\"confirm current pricing at https://aws.amazon.com/eks/pricing/\")))" "$TMP/eks/preflight.json" >/dev/null'
check "support: AKS LTS price WARN names checked 2026-10-18 and the AKS pricing page" 'jq -e "any(.findings[]; .object == \"AKS 1.34\" and (.message | contains(\"checked 2026-10-18\") and contains(\"confirm current pricing at https://azure.microsoft.com/en-us/pricing/details/kubernetes-service/\")))" "$TMP/aks-late/preflight.json" >/dev/null'
check "support: every support WARN that quotes a price carries the checked date and a pricing URL" '[ "$(cat "$TMP"/eks/preflight.json "$TMP"/aks-late/preflight.json | jq -s "[.[].findings[] | select(.category == \"support\" and (.message | test(\"\\\\$[0-9]\")))] | map(select((.message | contains(\"checked 2026-10-18\") and test(\"confirm current pricing at https://\")) | not)) | length")" -eq 0 ]'
# N1: the CURRENT minor's provider deadline (GKE 1.31 extended support ends 2026-10-22; EKS 1.31 ends 2026-11-26).
cp -R tests/fixtures/gke-clean "$TMP/gke131"
echo '{"server":"v1.31.9-gke.1000000","client":"v1.32.0"}' > "$TMP/gke131/version.json"
jq -c 'map(.kubelet = "v1.31.9-gke.1000000")' tests/fixtures/gke-clean/nodes.json > "$TMP/gke131/nodes.json"
pf --context gke-dev --target 1.32 --fixtures "$TMP/gke131" --out "$TMP/g131"
J="$TMP/g131/preflight.json"
check "support: GKE current 1.31 extended support ending 2026-10-22 is a WARN with the date" 'jq -e "any(.findings[]; .object == \"GKE 1.31 (current)\" and .severity == \"WARN\" and (.message | contains(\"2026-10-22\") and contains(\"automatically\")))" "$J" >/dev/null'
check "support: GKE 1.32 target price WARN names checked date and the GKE pricing page" 'jq -e "any(.findings[]; .object == \"GKE 1.32\" and (.message | contains(\"checked 2026-10-18\") and contains(\"https://cloud.google.com/kubernetes-engine/pricing\")))" "$J" >/dev/null'
check "support: EKS current 1.31 (ends 2026-11-26) is not flagged more than 30 days ahead" 'hasnt "$TMP/eks/preflight.json" support "EKS 1.31 (current)"'
PREFLIGHT_NOW="2026-11-01T00:00:00Z" pf --context eks-prod --target 1.32 --fixtures tests/fixtures/eks-skew --out "$TMP/eks-nov"
check "support: EKS current 1.31 within 30 days of end of extended support is a WARN (auto-upgrade, no rollback)" 'jq -e "any(.findings[]; .object == \"EKS 1.31 (current)\" and .severity == \"WARN\" and (.message | contains(\"2026-11-26\") and contains(\"rolled back\")))" "$TMP/eks-nov/preflight.json" >/dev/null'

# ---- operator-owned PDBs (CloudNativePG-style Cluster) and zonal PersistentVolumes ---------------
pf --context gke-dev --target 1.36 --fixtures tests/fixtures/operator-pdb --out "$TMP/op"; rc=$?
J="$TMP/op/preflight.json"
fx() { jq -r --arg o "$1" --arg k "$2" '[.findings[] | select(.object == $o)][0][$k] // ""' "$J"; }
check "operator pdb: 3-instance Cluster primary PDB is WARN, not BLOCKER" 'has "$J" WARN pdb pdb/db/pg-ha-primary && ! has "$J" BLOCKER pdb pdb/db/pg-ha-primary'
check "operator pdb: WARN says operator-managed, do not edit, check replicas" '[ -n "$(fx pdb/db/pg-ha-primary fix | grep "Managed by operator Cluster; do not edit or disable it" | grep ">=2 instances" | grep "caught up")" ]'
check "operator pdb: 1-instance Cluster primary PDB stays BLOCKER" 'has "$J" BLOCKER pdb pdb/db/pg-solo-primary'
check "operator pdb: BLOCKER fix is add a replica" '[ -n "$(fx pdb/db/pg-solo-primary fix | grep "Add a replica")" ]'
check "operator pdb: no fix ever suggests lowering, editing-down or disabling an operator PDB" '[ -z "$(jq -r ".findings[] | select(.ref | contains(\"cloudnative-pg\")) | .fix" "$J" | grep -iE "lower minAvailable|raise maxUnavailable|enablePDB|delete|disable (the|this) PDB" | grep -viE "do not edit or disable")" ]'
check "operator pdb: healthy replica PDB of the same Cluster is not reported" '! jq -e "any(.findings[]; .object == \"pdb/db/pg-ha\")" "$J" >/dev/null'
check "operator pdb: findings cite the CloudNativePG upgrade doc" '[ "$(fx pdb/db/pg-ha-primary ref)" = "https://cloudnative-pg.io/documentation/1.24/kubernetes_upgrade/" ]'
check "operator pdb: NO-GO only because of the single-instance Cluster (exit 1)" '[ $rc -eq 1 ] && [ "$(jq "[.findings[] | select(.severity == \"BLOCKER\")] | length" "$J")" -eq 1 ]'
check "zonal storage: StatefulSet with zonal PVs is WARN naming both zones" 'has "$J" WARN zonal-storage statefulset/stream/kafka && [ -n "$(fx statefulset/stream/kafka message | grep us-central1-a | grep us-central1-b)" ]'
check "zonal storage: fix asks for capacity in each zone" '[ -n "$(fx statefulset/stream/kafka fix | grep "surge or replacement capacity in each of")" ]'
check "zonal storage: StatefulSet whose PV has no zone is not flagged" '! has "$J" WARN zonal-storage statefulset/stream/cache'
check "zonal storage: CloudNativePG Cluster on zonal PVs is WARN naming the Cluster and its zones" 'has "$J" WARN zonal-storage cluster/db/pg-ha && [ -n "$(fx cluster/db/pg-ha message | grep "^Cluster pg-ha:" | grep us-central1-a | grep us-central1-b | grep us-central1-c)" ]'
check "zonal storage: operator pods are grouped per owner (single-instance Cluster reported separately)" 'has "$J" WARN zonal-storage cluster/db/pg-solo && [ "$(jq "[.findings[] | select(.category == \"zonal-storage\")] | length" "$J")" -eq 3 ]'
# Raw PV trimming (zones from node affinity and from the legacy label) through a stub kubectl.
mkdir -p "$TMP/pvstub"
cat > "$TMP/pvstub/kubectl" <<'STUB'
#!/bin/sh
case "$*" in
  *" version "*|*" version") echo '{"clientVersion":{"gitVersion":"v1.35.0"},"serverVersion":{"gitVersion":"v1.35.2-gke.1"}}' ;;
  *api-versions*) echo v1 ;;
  *persistentvolumes*) cat <<'JSON'
{"items":[{"metadata":{"name":"pv-aff"},"spec":{"nodeAffinity":{"required":{"nodeSelectorTerms":[{"matchExpressions":[{"key":"topology.kubernetes.io/zone","operator":"In","values":["z-a"]},{"key":"kubernetes.io/hostname","operator":"In","values":["n1"]}]}]}}}},
 {"metadata":{"name":"pv-legacy","labels":{"failure-domain.beta.kubernetes.io/zone":"z-b__z-c"}},"spec":{}},
 {"metadata":{"name":"pv-none"},"spec":{}}]}
JSON
  ;;
  *) echo '{"items":[]}' ;;
esac
STUB
chmod +x "$TMP/pvstub/kubectl"
PATH="$TMP/pvstub:$PATH" "$SH" scripts/upgrade-preflight.sh --context stub --target 1.36 --no-tools --out "$TMP/pvs" >/dev/null 2>&1
check "zonal storage: PV zones read from node affinity and legacy label" '[ "$(jq -c "map({(.name): .zones}) | add" "$TMP/pvs/raw/pvs.json")" = "{\"pv-aff\":[\"z-a\"],\"pv-legacy\":[\"z-b\",\"z-c\"],\"pv-none\":[]}" ]'

# ---- PSP coverage gap on a 1.24 -> 1.25 run points to the commented rule in the RBAC file --------
pf --context gke-old --target 1.25 --fixtures tests/fixtures/psp-gap --out "$TMP/psp"
J="$TMP/psp/preflight.json"
check "psp gap: could-not-check WARN for podsecuritypolicies" 'has "$J" WARN removed-api podsecuritypolicies.policy'
check "psp gap: fix points to the PodSecurityPolicy comment in references/rbac-preflight.yaml" '[ -n "$(jq -r "[.findings[] | select(.object == \"podsecuritypolicies.policy\")][0].fix" "$J" | grep "references/rbac-preflight.yaml (PodSecurityPolicy section)")" ] && grep -q "^# PodSecurityPolicy (1.24 to 1.25 upgrades only)" references/rbac-preflight.yaml && grep -q "^#   resources: \[\"podsecuritypolicies\"\]" references/rbac-preflight.yaml'
check "psp gap: other could-not-list findings keep the generic fix" '[ -z "$(jq -r ".findings[] | select(.category == \"removed-api\" and (.message | startswith(\"Could not list\")) and .object != \"podsecuritypolicies.policy\") | .fix" "$J" | grep rbac-preflight)" ]'

# ---- verify-step.sh against a recorded mid-upgrade state ---------------------------------------
vf() { "$SH" scripts/verify-step.sh "$@" >"$TMP/last.out" 2>&1; }
vf --expect-control-plane 1.32 --fixtures tests/fixtures/verify-after-pool; check "verify: missing --context is refused (exit 2)" '[ $? -eq 2 ]'
vf --context x --expect-pool ng-a --fixtures tests/fixtures/verify-after-pool; check "verify: --expect-pool without --expect-nodes is refused" '[ $? -eq 2 ]'
vf --context x --expect-nodes 1.32 --fixtures tests/fixtures/verify-after-pool --out "$TMP/vall"
check "verify: --expect-nodes alone compares every node and names the laggard" '[ "$(jq -r ".checks[] | select(.check == \"all nodes at 1.32\") | .result" "$TMP/vall/verify.json")" = FAIL ] && jq -r ".checks[].detail" "$TMP/vall/verify.json" | grep -q "ip-10-0-2-10=v1.31"'
vf --context x --pool-label "bad label" --fixtures tests/fixtures/verify-after-pool; check "verify: malformed --pool-label is refused" '[ $? -eq 2 ]'
# --pool-label on a cluster without provider pool labels (kind/kubeadm), through a stub kubectl.
mkdir -p "$TMP/vstub"
cat > "$TMP/vstub/kubectl" <<'STUB'
#!/bin/sh
case "$*" in
  *"config get-contexts"*) exit 0 ;;
  *" version "*) echo '{"serverVersion":{"gitVersion":"v1.32.3"}}' ;;
  *" get nodes"*) cat <<'JSON'
{"items":[
 {"metadata":{"name":"w1","labels":{"example.com/pool":"workers"}},"spec":{},"status":{"nodeInfo":{"kubeletVersion":"v1.32.3"},"conditions":[{"type":"Ready","status":"True"}]}},
 {"metadata":{"name":"w2","labels":{"example.com/pool":"workers"}},"spec":{},"status":{"nodeInfo":{"kubeletVersion":"v1.32.3"},"conditions":[{"type":"Ready","status":"True"}]}},
 {"metadata":{"name":"cp","labels":{}},"spec":{},"status":{"nodeInfo":{"kubeletVersion":"v1.31.9"},"conditions":[{"type":"Ready","status":"True"}]}}]}
JSON
  ;;
  *) echo '{"items":[]}' ;;
esac
STUB
chmod +x "$TMP/vstub/kubectl"
PATH="$TMP/vstub:$PATH" vf --context kind-x --expect-pool workers --expect-nodes 1.32 --pool-label example.com/pool --out "$TMP/vpl"; rc=$?
check "verify: --pool-label groups nodes by that label (pool workers PASS)" '[ $rc -eq 0 ] && [ "$(jq -r ".checks[] | select(.check == \"pool workers at 1.32\") | .result" "$TMP/vpl/verify.json")" = PASS ]'

# N5: --pool-label in fixture mode, from recorded node labels.
cp -R tests/fixtures/verify-after-pool "$TMP/vlab"
jq -c 'map(.labels = {"example.com/pool": ("x-" + .pool)})' tests/fixtures/verify-after-pool/nodes.json > "$TMP/vlab/nodes.json"
vf --context x --expect-nodes 1.32 --expect-pool x-ng-a --pool-label example.com/pool --fixtures "$TMP/vlab" --out "$TMP/vlab-out"
check "verify: --pool-label is applied in fixture mode (pool x-ng-a PASS)" '[ "$(jq -r ".checks[] | select(.check == \"pool x-ng-a at 1.32\") | .result" "$TMP/vlab-out/verify.json")" = PASS ]'
vf --context x --expect-nodes 1.32 --expect-pool ng-a --pool-label example.com/pool --fixtures tests/fixtures/verify-after-pool --out "$TMP/vnolab"
check "verify: fixtures without node labels say --pool-label could not be applied" 'grep -q "could not be applied" "$TMP/last.out"'
# N8: preflight node pools honour --pool-label.
cp -R tests/fixtures/kind-1.31 "$TMP/kindlab"
jq -c 'map(.labels = (if (.name | test("worker")) then {"example.com/pool": "workers"} else {} end))' tests/fixtures/kind-1.31/nodes.json > "$TMP/kindlab/nodes.json"
pf --context kind-x --target 1.32 --pool-label example.com/pool --fixtures "$TMP/kindlab" --out "$TMP/kindlab-out"
check "preflight: --pool-label groups node pools by that label" '[ "$(jq -r "[.. | .node_pools? // empty | .[] | select(.pool == \"workers\") | .nodes][0] // 0" "$TMP/kindlab-out/preflight.json")" -ge 1 ]'
pf --context kind-x --target 1.32 --pool-label example.com/pool --fixtures tests/fixtures/kind-1.31 --out "$TMP/kindnolab"
check "preflight: fixtures without node labels give an INFO that --pool-label was not applied" 'has "$TMP/kindnolab/preflight.json" INFO coverage "node pools"'
pf --context kind-x --target 1.32 --pool-label "bad label" --fixtures tests/fixtures/kind-1.31; check "preflight: malformed --pool-label is refused" '[ $? -eq 2 ]'
# N4: two runs in the same second get different directories (date pinned through a stub).
mkdir -p "$TMP/datestub" "$TMP/same"
printf '#!/bin/sh\necho 20261018T120000Z\n' > "$TMP/datestub/date"; chmod +x "$TMP/datestub/date"
for i in 1 2; do
  PATH="$TMP/datestub:$PATH" TMPDIR="$TMP/same" "$SH" scripts/upgrade-preflight.sh --context same --target 1.32 --fixtures tests/fixtures/kind-1.31 >/dev/null 2>&1
  PATH="$TMP/datestub:$PATH" TMPDIR="$TMP/same" "$SH" scripts/verify-step.sh --context same --fixtures tests/fixtures/verify-after-pool >/dev/null 2>&1
done
check "same-second preflight runs get two separate directories" '[ "$(ls -d "$TMP"/same/k8sup-same-1.32-20261018T120000Z.* | wc -l | tr -d " ")" -eq 2 ] && [ "$(ls "$TMP"/same/k8sup-same-1.32-20261018T120000Z.*/preflight.json | wc -l | tr -d " ")" -eq 2 ]'
check "same-second verify runs get two separate directories" '[ "$(ls -d "$TMP"/same/k8sup-verify-same-20261018T120000Z.* | wc -l | tr -d " ")" -eq 2 ]'
check "default output directories are mode 700" '[ "$(ls -ld "$(ls -d "$TMP"/same/k8sup-same-1.32-* | head -n 1)" | cut -c1-10)" = drwx------ ]'

# ---- scripts/preflight-kubeconfig.sh (credential helper), through a stub kubectl ----------------
mkdir -p "$TMP/kstub"
cat > "$TMP/kstub/kubectl" <<STUB
#!/bin/sh
echo "\$*" >> "$TMP/kstub/args"
case "\$*" in
  *"config get-contexts"*) exit 0 ;;
  *"cluster.server"*) printf 'https://127.0.0.1:6443' ;;
  *"certificate-authority-data"*) printf 'Q0FEQVRB' ;;
  *"certificate-authority"*) printf '' ;;
  *"create token"*) printf 'SECRET-TEST-TOKEN' ;;
esac
STUB
chmod +x "$TMP/kstub/kubectl"
PATH="$TMP/kstub:$PATH" "$SH" scripts/preflight-kubeconfig.sh --duration 1h >/dev/null 2>&1; check "kubeconfig helper: missing --context is refused" '[ $? -eq 2 ]'
PATH="$TMP/kstub:$PATH" "$SH" scripts/preflight-kubeconfig.sh --context admin --duration 48h >/dev/null 2>&1; check "kubeconfig helper: duration over 24h is refused" '[ $? -eq 2 ]'
check "kubeconfig helper: refusals never asked for a token" '! grep -q "create token" "$TMP/kstub/args" 2>/dev/null'
KCOUT="$(PATH="$TMP/kstub:$PATH" TMPDIR="$TMP" "$SH" scripts/preflight-kubeconfig.sh --context admin --duration 30m 2>&1)"
check "kubeconfig helper: token requested for kube-system/upgrade-preflight with --duration" 'grep -q -- "--context admin -n kube-system create token upgrade-preflight --duration 30m" "$TMP/kstub/args"'
check "kubeconfig helper: token is never printed" '! printf "%s" "$KCOUT" | grep -q SECRET-TEST-TOKEN'
check "kubeconfig helper: kubeconfig is mode 600 in a mode 700 dir outside the skill" '[ -f "$KCOUT" ] && [ "$(ls -l "$KCOUT" | cut -c1-10)" = "-rw-------" ] && [ "$(ls -ld "$(dirname "$KCOUT")" | cut -c1-10)" = "drwx------" ] && case "$KCOUT" in "$SKILL"*) false ;; *) true ;; esac'
check "kubeconfig helper: context upgrade-preflight-ro with CA, no insecure-skip" 'grep -q "name: upgrade-preflight-ro" "$KCOUT" && grep -q certificate-authority-data "$KCOUT" && ! grep -q insecure "$KCOUT"'
vf --context eks-prod --expect-control-plane 1.32 --expect-pool ng-a --expect-nodes 1.32 --fixtures tests/fixtures/verify-after-pool --out "$TMP/v1"; rc=$?
V="$TMP/v1/verify.json"
vres() { jq -r --arg c "$1" '.checks[] | select(.check == $c) | .result' "$V"; }
check "verify: FAIL exits 1" '[ $rc -eq 1 ] && [ "$(jq -r .result "$V")" = FAIL ]'
check "verify: control plane at 1.32 passes" '[ "$(vres "control-plane version")" = PASS ]'
check "verify: upgraded pool ng-a passes" '[ "$(vres "pool ng-a at 1.32")" = PASS ]'
check "verify: cordoned node fails" '[ "$(vres "nodes schedulable")" = FAIL ]'
check "verify: DaemonSet not fully ready fails" '[ "$(vres "kube-system DaemonSets ready")" = FAIL ]'
check "verify: Pending pod fails" '[ "$(vres "no Pending/Failed/crash-looping pods")" = FAIL ]'
vf --context eks-prod --expect-control-plane 1.33 --fixtures tests/fixtures/verify-after-pool --out "$TMP/v2"
V="$TMP/v2/verify.json"
check "verify: wrong control-plane minor fails" '[ "$(vres "control-plane version")" = FAIL ]'
vf --context eks-prod --expect-pool ng-b --expect-nodes 1.32 --fixtures tests/fixtures/verify-after-pool --out "$TMP/v3"
V="$TMP/v3/verify.json"
check "verify: pool still on the old minor fails" '[ "$(vres "pool ng-b at 1.32")" = FAIL ]'

# ---- live kind cluster --------------------------------------------------------------------------
if [ "$KIND" = 1 ]; then
  NAME="${KIND_CLUSTER:-k8sup-preflight-test}"
  IMAGE="${KIND_NODE_IMAGE:-kindest/node:v1.31.14@sha256:6f86cf509dbb42767b6e79debc3f2c32e4ee01386f0489b3b2be24b0a55aac2b}"
  RT=""
  if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then RT=docker
  elif command -v podman >/dev/null 2>&1; then RT=podman; export KIND_EXPERIMENTAL_PROVIDER=podman; fi
  if [ -z "$RT" ] || ! command -v kind >/dev/null 2>&1 || ! command -v kubectl >/dev/null 2>&1; then
    no "kind tests need docker or podman, kind and kubectl on PATH"
  else
    KC="$TMP/kubeconfig"; ( umask 077; : > "$KC" )
    cleanup() { if [ "$KEEP" = 0 ]; then kind delete cluster --name "$NAME" --kubeconfig "$KC" >/dev/null 2>&1; rm -rf "$TMP"; fi; }
    trap cleanup EXIT
    sed "s#AUDIT_POLICY_PATH#$SKILL/tests/kind-audit-policy.yaml#" tests/kind-config.yaml > "$TMP/kind-config.yaml"
    if kind create cluster --name "$NAME" --image "$IMAGE" --config "$TMP/kind-config.yaml" --kubeconfig "$KC" --wait 180s >"$TMP/kind.log" 2>&1; then
      ok "kind cluster $NAME created ($IMAGE)"
      ADMIN="kind-$NAME"
      ka() { kubectl --kubeconfig "$KC" --context "$ADMIN" "$@"; }
      ka apply -f tests/kind-seed.yaml >"$TMP/seed.log" 2>&1 && ka apply -f references/rbac-preflight.yaml >>"$TMP/seed.log" 2>&1
      check "seed objects and get/list-only RBAC applied" '[ $? -eq 0 ]'
      ka -n upgrade-test rollout status deploy/web --timeout=180s >/dev/null 2>&1
      ka -n upgrade-test rollout status deploy/solo --timeout=180s >/dev/null 2>&1
      ka -n upgrade-test wait pod/bare --for=condition=Ready --timeout=180s >/dev/null 2>&1
      ka -n upgrade-test rollout status sts/zonal --timeout=180s >/dev/null 2>&1
      # A second context that authenticates as the get/list-only ServiceAccount.
      TOKEN="$(ka -n kube-system create token upgrade-preflight --duration=1h)"
      SERVER="$(ka config view --raw --minify -o jsonpath='{.clusters[0].cluster.server}')"
      CA="$(ka config view --raw --minify -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')"
      ( umask 077; printf 'apiVersion: v1\nkind: Config\nclusters:\n- name: ro\n  cluster: {server: "%s", certificate-authority-data: "%s"}\nusers:\n- name: ro\n  user: {token: "%s"}\ncontexts:\n- name: preflight-ro\n  context: {cluster: ro, user: ro}\n' "$SERVER" "$CA" "$TOKEN" > "$TMP/ro.kubeconfig" )
      unset TOKEN
      CUR="$(ka version -o json | jq -r '.serverVersion.minor' | tr -dc '0-9')"; NEXT="1.$((CUR + 1))"
      KUBECONFIG="$TMP/ro.kubeconfig" pf --context preflight-ro --target "$NEXT" --out "$TMP/live"; rc=$?
      J="$TMP/live/preflight.json"
      check "live: preflight ran as the get/list-only identity and returned NO-GO (exit 1)" '[ $rc -eq 1 ] && [ "$(verdict "$J")" = NO-GO ]'
      check "live: PDB maxUnavailable 0 found" 'has "$J" BLOCKER pdb upgrade-test/web-pdb'
      check "live: PDB minAvailable = replicas found" 'has "$J" BLOCKER pdb upgrade-test/solo-pdb'
      check "live: single-replica Deployment found" 'has "$J" WARN single-replica deployment/upgrade-test/solo'
      check "live: bare pod with emptyDir found" 'has "$J" WARN bare-pod pod/upgrade-test/bare && has "$J" WARN local-storage pod/upgrade-test/bare'
      check "live: StatefulSet with zonal PVs found, naming both zones" 'jq -e "any(.findings[]; .severity == \"WARN\" and .category == \"zonal-storage\" and .object == \"statefulset/upgrade-test/zonal\" and (.message | contains(\"kind-zone-a\") and contains(\"kind-zone-b\")))" "$J" >/dev/null'
      check "live: Fail webhook with missing service found" 'has "$J" BLOCKER webhook upgrade-test-broken'
      if [ "$CUR" -lt 32 ]; then
        check "live: FlowSchema written via v1beta3 found" 'has "$J" BLOCKER removed-api FlowSchema/upgrade-test-legacy'
        check "live: deprecated-API metric found (folded into the FlowSchema finding)" 'jq -e "any(.findings[]; .object == \"FlowSchema/upgrade-test-legacy\" and (.sources | index(\"deprecated-API metric\")))" "$J" >/dev/null'
      fi
      check "live: no coverage gaps with the shipped RBAC" 'hasnt "$J" coverage ""'
      lverbs="$(grep -vE '^(kubent|pluto) ' "$TMP/live/raw/calls.log" | awk '{print $1}' | sort -u | tr '\n' ' ')"
      check "live: calls.log holds only get/version/api-versions (found: $lverbs)" '[ -z "$(printf "%s\n" $lverbs | grep -vxE "get|version|api-versions")" ]'
      # Independent evidence: what the API server recorded for the get/list-only identity.
      "$RT" exec "$NAME-control-plane" cat /var/log/kubernetes/kube-apiserver-audit.log > "$TMP/audit.log" 2>/dev/null
      U="system:serviceaccount:kube-system:upgrade-preflight"
      averbs="$(jq -r --arg u "$U" 'select(.user.username == $u and .stage == "ResponseComplete") | .verb' "$TMP/audit.log" | sort -u | tr '\n' ' ')"
      check "audit: API server saw only get/list from the preflight identity (found: $averbs)" '[ -n "$averbs" ] && [ -z "$(printf "%s\n" $averbs | grep -vxE "get|list")" ]'
      check "audit: preflight identity never touched secrets or configmaps" '[ -z "$(jq -r --arg u "$U" "select(.user.username == \$u and ((.objectRef.resource // \"\") | test(\"^(secrets|configmaps)$\"))) | .verb" "$TMP/audit.log")" ]'
      KUBECONFIG="$TMP/ro.kubeconfig" vf --context preflight-ro --expect-control-plane "1.$CUR" --out "$TMP/lv1"; rc=$?
      check "live verify: healthy seeded cluster passes at 1.$CUR (exit 0)" '[ $rc -eq 0 ]'
      KUBECONFIG="$TMP/ro.kubeconfig" vf --context preflight-ro --expect-control-plane "$NEXT" --out "$TMP/lv2"; rc=$?
      check "live verify: expecting $NEXT before the upgrade fails (exit 1)" '[ $rc -eq 1 ]'
      ka -n upgrade-test create deployment broken --image=registry.invalid/does-not-exist:0 >/dev/null 2>&1
      sleep 20
      KUBECONFIG="$TMP/ro.kubeconfig" vf --context preflight-ro --out "$TMP/lv3"; rc=$?
      check "live verify: image-pull failure is caught (exit 1)" '[ $rc -eq 1 ] && jq -e "any(.checks[]; .result == \"FAIL\" and (.detail | contains(\"upgrade-test/broken\")))" "$TMP/lv3/verify.json" >/dev/null'
      vverbs="$(cat "$TMP/lv1/raw/calls.log" "$TMP/lv3/raw/calls.log" | awk '{print $1}' | sort -u | tr '\n' ' ')"
      check "live verify: only get/version calls (found: $vverbs)" '[ -z "$(printf "%s\n" $vverbs | grep -vxE "get|version")" ]'
      if [ -n "$RECORD" ]; then
        mkdir -p "$RECORD" && cp "$TMP/live/raw/"*.json "$RECORD/" && ok "recorded trimmed inputs to $RECORD"
      fi
    else
      no "kind cluster create failed (see $TMP/kind.log)"; cat "$TMP/kind.log"
    fi
  fi
fi

check "the suite left the skill tree unchanged (no stray output folders)" '[ "$(tree_sum)" = "$TREE_BEFORE" ]'
echo "# $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && rm -rf "${TMP:?}"
[ "$FAIL" -eq 0 ]
