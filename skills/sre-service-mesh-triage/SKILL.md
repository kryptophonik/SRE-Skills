---
name: sre-service-mesh-triage
description: "Use when Istio or Linkerd sidecars are suspected: 503s from the mesh vs. the app, mTLS handshake failures, retry/circuit-breaker storms, sidecar injection failures, egress blocked by policy. Read-only; fixes hand off to sre-k8s-safe-remediation."
---

# Service mesh triage

## Safety gates (REQUIRED)

1. Read-only diagnosis first.
2. Propose each change with risk (low/med/high) and reversibility.
3. Wait for explicit human approval before any prod-changing command, MCP write tool, or external post.
4. Act only as approved, verify, and stop and escalate if anything gets worse.

Full rules: [sre-safety-gates](../sre-safety-gates/SKILL.md). Read-only MCP setup: [sre-safety-gates/references/mcp.md](../sre-safety-gates/references/mcp.md).

This skill is read-only end to end. It never applies a mesh config change, restarts a sidecar, or deletes a pod itself — every fix it finds hands off to `sre-k8s-safe-remediation` (manual only) or to a config change through `sre-change-safety`/GitOps. Process skills: `sre-incident-command`, `sre-engineer` / `sre-diagnostics`, `sre-k8s-triage` (workload-level triage, which this skill complements, not replaces).

## Rules

- **Every command carries `--context <ctx> -n <ns>`.** Never rely on the current context.
- **Mesh-level and app-level 5xxs look identical to a user.** Always check the mesh's own view (Envoy response flags, Istio/Linkerd proxy status) before assuming the backend is broken.
- **Never `kubectl exec` into a pod to poke at a sidecar.** Use the proxy's own read-only admin/metrics endpoints via port-forward, or the mesh CLI's own status commands. An `exec` into a mesh-managed pod goes through `sre-k8s-triage`/`sre-k8s-safe-remediation`'s own approval gate, not this skill.
- **mTLS and retry/circuit-breaker config is a shared, cluster-wide blast radius.** A change to a `PeerAuthentication`, `DestinationRule`, or `AuthorizationPolicy` can affect every service in the mesh, not just the one paging. Treat any such change as high risk by default.
- **Never without explicit approval:** `istioctl install`/`upgrade`, any `kubectl apply`/`edit`/`patch` to `VirtualService`/`DestinationRule`/`PeerAuthentication`/`AuthorizationPolicy`/`Gateway`, restarting or re-injecting sidecars, `linkerd upgrade`, disabling mTLS anywhere.

## Decision tree by symptom

| Symptom | Likely cause | Check |
|---|---|---|
| 503 `UC`/`UF`/`UO` (Envoy response flags) | Upstream connection failure, outlier detection ejected the host, overflow (circuit breaker tripped) | `istioctl proxy-config`/Envoy admin `/clusters` for the affected cluster's health; is this a real backend outage or the breaker being too aggressive |
| 503 with no app-level error in the backend's own logs | The request never reached the app — mesh-level rejection (authz policy, no healthy endpoint, mTLS handshake failure) | `istioctl analyze`, `PeerAuthentication`/`AuthorizationPolicy` for the namespace, sidecar readiness |
| Intermittent failures that "fixed themselves" | Retry storm amplifying a transient backend blip into sustained load, or outlier detection flapping a host in/out | retry policy (`DestinationRule` `retries`/`outlierDetection`) vs. backend's own error rate over the same window |
| New pod never gets traffic | Sidecar injection failed or pod isn't in the mesh, readiness probe on the sidecar itself not passing | `kubectl get pod -o jsonpath` for the `istio-proxy`/`linkerd-proxy` container, `istioctl proxy-status` for `SYNCED` |
| mTLS handshake errors between two services | `PeerAuthentication` mode mismatch (STRICT vs PERMISSIVE), mismatched or expired mesh-issued certs, one side not injected | `istioctl proxy-config secret`, `linkerd check --proxy`, whether both sides are actually in the mesh |
| Egress calls to an external host blocked or timing out | `ServiceEntry`/`Sidecar` egress policy, or mesh set to block-by-default | `istioctl analyze`, egress traffic policy for the namespace |
| Everything in the mesh degrades at once | Control plane (istiod / linkerd-destination) itself unhealthy, or a cluster-wide policy change just landed | control plane pod health first, then `sre-change-safety` for what changed |

## Read-only commands

### Istio

```bash
istioctl proxy-status                                          # SYNCED/STALE per pod, control plane view
istioctl proxy-config clusters <pod>.<ns> --fqdn <svc>.<ns>.svc.cluster.local   # health, outlier detection state
istioctl proxy-config endpoints <pod>.<ns> --cluster '<cluster-name>'
istioctl proxy-config secret <pod>.<ns>                          # mTLS cert status (not the key)
istioctl analyze -n <ns>                                         # static config problems, misconfigured policies
kubectl --context <ctx> -n <ns> get peerauthentication,destinationrule,authorizationpolicy,virtualservice
kubectl --context <ctx> -n istio-system get pods                # control plane health
```

Envoy admin endpoint, read-only, via port-forward (no exec needed):

```bash
kubectl --context <ctx> -n <ns> port-forward <pod> 15000:15000 &   # Ctrl-C or close this shell when done
curl -s localhost:15000/clusters | grep -i <upstream-cluster>     # per-upstream health, outlier ejection state
curl -s localhost:15000/stats | grep -i circuit_breakers          # breaker trip counts
```

Envoy response-flag quick reference: `UC` = upstream connection termination, `UF` = upstream connection failure, `UO` = upstream overflow (circuit breaker open), `NR` = no route configured, `URX` = retry limit exceeded.

### Linkerd

```bash
linkerd check                          # control plane and data plane health
linkerd check --proxy                  # per-namespace proxy injection/version checks
linkerd viz stat deploy -n <ns>         # success rate, RPS, latency per deployment, mesh's own view
linkerd viz stat deploy <name> -n <ns> --to deploy/<other>   # traffic between two specific services
linkerd viz tap deploy/<name> -n <ns> --to deploy/<other> -o wide   # live request sample, bounded; Ctrl-C to stop
linkerd viz edges deploy -n <ns>       # which services are meshed and talking, mTLS status per edge
```

`linkerd viz tap` is a live stream: always run it with a visible end condition (short wall-clock window or `--max-rps`), never unbounded in prod.

## Correlating mesh vs. app

1. Mesh says 503 (Envoy `UC`/`UO`, or Linkerd shows a failed edge): check the backend's **own** logs and `sre-k8s-triage`'s readiness-probe/restart-safety checks for the same window — if the app saw no request, the problem is in the mesh layer (policy, mTLS, breaker), not the app.
2. App shows errors but the mesh's edge/cluster view looks healthy: this is an app problem, not a mesh problem — hand off to `sre-diagnostics`/`sre-database-triage` rather than touching mesh config.
3. Both look healthy but users still see failures: check the ingress/gateway layer itself (`istioctl proxy-status` for the gateway pod, `linkerd viz stat` on the ingress deployment) — the mesh might not be in the path you think it is.

## Fix order when the mesh is implicated

Every one of these is a config change outside this skill's own write boundary — propose, get approval, then apply through GitOps/`sre-change-safety` or hand restart/pod-level fixes to `sre-k8s-safe-remediation`.

1. If a recent policy or `DestinationRule`/`VirtualService` change correlates with the onset: revert that change in Git first (same GitOps-preferred pattern as `sre-k8s-safe-remediation`), rather than hand-patching live objects.
2. If outlier detection/circuit breaking is ejecting a host that is actually healthy (e.g. a slow but working backend): loosening the breaker is a judgment call for the service owner, not an on-call reflex — propose with the tradeoff stated (less protection for the backend vs. more availability now).
3. If mTLS mode mismatch is the cause: fixing `PeerAuthentication` mode is cluster/namespace-wide — confirm no other service depends on the current mode before proposing a change.
4. If sidecar injection failed on a new pod: the fix is almost always a rollout restart after confirming the namespace/pod injection label is correct — that restart runs through `sre-k8s-safe-remediation`.
5. Control plane itself unhealthy: this is infra-team territory, escalate rather than attempting a control-plane restart from an incident channel.

## Output

- Target (cluster, namespace, mesh — Istio/Linkerd, version), evidence (proxy-status/clusters/stat output with timestamps), whether the failure originated at the mesh layer or the app layer, likely cause and confidence, proposed fix with risk/reversibility and the approver, verification result.

## Stop and escalate

- The control plane itself (istiod, linkerd-destination) is unhealthy: every service in the mesh is at risk, escalate immediately rather than triaging one service's symptoms.
- A proposed policy change would affect services outside the one currently paging: get the other services' owners into the approval before proceeding.
- mTLS can't be established and the only available fix is disabling it: don't propose disabling mTLS as an incident fix — escalate for a security-aware decision.

Last reviewed: 2026-10-23
