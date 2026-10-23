# Example 10: the same crash-loop, but this is the real AI session

**Skills:** [sre-k8s-triage](../../.claude/skills/sre-k8s-triage/SKILL.md) for the diagnosis, then [sre-k8s-safe-remediation](../../.claude/skills/sre-k8s-safe-remediation/SKILL.md) for the rollback.

> **What's different about this page.** [Example 1](01-k8s-crashloop-rollback.md) is "written in the skill's format" — the shape of the answer, not a transcript. This page is the opposite: every command, every output and every stop below is copied from one real Claude Code session on 2026-10-23 that actually loaded `sre-k8s-triage` and `sre-k8s-safe-remediation` through the `Skill` tool and ran them against a live kind cluster. Nothing here is reconstructed after the fact. kind v0.33.0 (node image v1.37.0), kubectl v1.33, Docker Desktop on macOS. The only edits below are trimming repeated `Pulling fs layer` lines and replacing the kubeconfig's temp path.

## What this shows that example 1 doesn't

- The skill genuinely invoked via the `Skill` tool, not an operator narrating it.
- `sre-k8s-safe-remediation` refusing to be invoked that way at all: it's `disable-model-invocation`, so the agent cannot run it on its own initiative even with a green light from the first skill. The human had to type `/sre-k8s-safe-remediation` themselves.
- A real divergence from the example 1 script: this cluster's Deployment has no readiness probe, so the rollout didn't leave one old pod standing — **both** pods flipped to the bad revision before either new pod proved healthy. `ready=` came back **empty** (0), not 1. Same root cause, worse blast radius, because this run didn't rig the timing.
- Two separate approval gates in sequence, both genuinely held for a typed "approved, run it" from the human, not assumed.

## Lab setup

```console
$ which kind kubectl docker
kind not found
/usr/local/bin/kubectl
/opt/homebrew/bin/docker
$ brew install kind
🍺  /opt/homebrew/Cellar/kind/0.33.0: 10 files, 10.5MB
$ open -a Docker   # waited for `docker info` to succeed
$ export KUBECONFIG=$(mktemp)
$ kind create cluster --name sre-demo --wait 120s
...
 ✓ Ready after 18s 💚
Set kubectl context to "kind-sre-demo"
$ docker pull nginx:1.27 && kind load docker-image nginx:1.27 --name sre-demo
...
ERROR: failed to load image: ... ctr: content digest sha256:fafd5f55...: not found
```

The `kind load docker-image` step actually failed on this run (a real containerd digest mismatch on this host) — and it didn't matter, because the node pulled `nginx:1.27` itself when the Deployment was created. That's a live example of a lab step failing harmlessly; the walkthrough continued without working around it.

```console
$ kubectl --context kind-sre-demo create namespace demo
$ kubectl --context kind-sre-demo -n demo create deployment web --image=nginx:1.27 --replicas=2 --port=80
$ kubectl --context kind-sre-demo -n demo annotate deployment web kubernetes.io/change-cause='v1: nginx 1.27' --overwrite
$ kubectl --context kind-sre-demo -n demo expose deployment web --port=80
$ kubectl --context kind-sre-demo -n demo rollout status deployment/web --timeout=120s
deployment "web" successfully rolled out
$ kubectl --context kind-sre-demo -n demo get pods -o wide
NAME                   READY   STATUS    RESTARTS   AGE   IP           NODE
web-557577df75-5c8vg   1/1     Running   0          18s   10.244.0.6   sre-demo-control-plane
web-557577df75-qrd7s   1/1     Running   0          18s   10.244.0.5   sre-demo-control-plane
```

## What broke

Same fault as example 1: revision 2 swaps the entrypoint for one that needs a config file the pod doesn't have.

```console
$ kubectl --context kind-sre-demo -n demo patch deployment web --type=json -p='[{"op":"add","path":"/spec/template/spec/containers/0/command","value":["sh","-c","echo loading config /etc/web/app.conf; echo FATAL: config file not found >&2; exit 1"]}]'
deployment.apps/web patched
$ kubectl --context kind-sre-demo -n demo annotate deployment web kubernetes.io/change-cause='v2: new entrypoint' --overwrite
$ kubectl --context kind-sre-demo -n demo get pods
NAME                   READY   STATUS   RESTARTS      AGE
web-664b48bf8f-fsqg7   0/1     Error    2 (15s ago)   16s
web-664b48bf8f-qmkqq   0/1     Error    2 (14s ago)   15s
```

Both replicas are already on the bad revision — the old `web-557577df75` pods are gone. No readiness probe means the rolling update doesn't wait for a new pod to prove healthy before taking down an old one.

## What was actually typed to invoke the skill

```
Skill(sre-k8s-triage, "A pod in namespace demo on kind-sre-demo keeps restarting since the last deploy. What's wrong?")
```

The skill tool returned the full `sre-k8s-triage` instructions (safety gates, the decision tree, the never-without-approval list, the bundled scripts) into context. From there the diagnosis below ran as real `kubectl` calls chosen against that decision tree, not a scripted order.

## The real triage run

**1. Pin the context, then pods and Warning events:**

```console
$ kubectl config get-contexts kind-sre-demo
CURRENT   NAME            CLUSTER         AUTHINFO        NAMESPACE
*         kind-sre-demo   kind-sre-demo   kind-sre-demo
$ kubectl --context kind-sre-demo -n demo get pods -o wide
NAME                   READY   STATUS   RESTARTS      AGE   IP
web-664b48bf8f-fsqg7   0/1     Error    2 (28s ago)   29s   10.244.0.7
web-664b48bf8f-qmkqq   0/1     Error    2 (27s ago)   28s   10.244.0.8
$ kubectl --context kind-sre-demo -n demo events --types=Warning | tail -n 50
LAST SEEN           TYPE      REASON    OBJECT                     MESSAGE
17s (x2 over 27s)   Warning   BackOff   Pod/web-664b48bf8f-fsqg7   Back-off restarting failed container nginx ...
16s (x2 over 26s)   Warning   BackOff   Pod/web-664b48bf8f-qmkqq   Back-off restarting failed container nginx ...
```

**2. Describe the pod** for the exit code:

```console
$ kubectl --context kind-sre-demo -n demo describe pod web-664b48bf8f-fsqg7 | sed -n '/^Containers:/,/^Conditions:/p'
    Command:
      sh
      -c
      echo loading config /etc/web/app.conf; echo FATAL: config file not found >&2; exit 1
    State:          Terminated
      Reason:       Error
      Exit Code:    1
    Last State:     Terminated
      Reason:       Error
      Exit Code:    1
    Ready:          False
    Restart Count:  2
```

**3. Logs.** `--previous` really did fail on this cluster, exactly as the skill's decision tree says it can:

```console
$ kubectl --context kind-sre-demo -n demo logs web-664b48bf8f-fsqg7 -c nginx --previous --tail=200
unable to retrieve container logs for containerd://cba412390e64e37004d97d765421df7cc279e6ee2ea55de114af814b5b8162f3
$ kubectl --context kind-sre-demo -n demo logs web-664b48bf8f-fsqg7 -c nginx --tail=200
loading config /etc/web/app.conf
FATAL: config file not found
```

**4. Nodes and rollout:**

```console
$ kubectl --context kind-sre-demo get nodes
NAME                     STATUS   ROLES           VERSION
sre-demo-control-plane   Ready    control-plane   v1.37.0
$ kubectl --context kind-sre-demo -n demo rollout history deployment/web
REVISION  CHANGE-CAUSE
1         v1: nginx 1.27
2         v2: new entrypoint
$ kubectl --context kind-sre-demo -n demo get deployment/web -o jsonpath='desired={.spec.replicas} ready={.status.readyReplicas} updated={.status.updatedReplicas}{"\n"}'
desired=2 ready= updated=2
$ kubectl --context kind-sre-demo -n demo get deployment/web -o jsonpath='{range .spec.template.spec.containers[*]}{.name}: readiness={.readinessProbe}{"\n"}{end}'
nginx: readiness=
```

`ready=` is blank — zero ready replicas, both desired pods on the bad revision. That's worse than example 1's `ready=2 updated=1`, and it's the genuine consequence of this Deployment never having a readiness probe: nothing gated the rollout.

**5. Ownership, then preflight and snapshot:**

```console
$ kubectl --context kind-sre-demo -n demo get pod web-664b48bf8f-fsqg7 -o jsonpath='{.metadata.ownerReferences[0].kind}/{.metadata.ownerReferences[0].name}{"\n"}'
ReplicaSet/web-664b48bf8f
$ kubectl --context kind-sre-demo -n demo get pdb
No resources found in demo namespace.
$ kubectl --context kind-sre-demo -n demo get hpa
No resources found in demo namespace.
$ cd .claude/skills/sre-k8s-triage
$ bash scripts/k8s-preflight.sh --context kind-sre-demo -n demo
context=kind-sre-demo namespace=demo identity=<kubeconfig user>
OK    can-i get pods                     => yes (want yes)
OK    can-i list events                  => yes (want yes)
OK    can-i get pods/log                 => yes (want yes)
FAIL  can-i get secrets                  => yes (want no)
FAIL  can-i list secrets                 => yes (want no)
FAIL  can-i create pods/exec             => yes (want no)
FAIL  can-i create pods/attach           => yes (want no)
FAIL  can-i create pods/portforward      => yes (want no)
FAIL  can-i delete pods                  => yes (want no)
FAIL  can-i patch deployments            => yes (want no)
FAIL  can-i create deployments           => yes (want no)
FAIL  can-i delete namespaces            => yes (want no)
[exit 1]
$ SNAP=$(mktemp -d)
$ bash scripts/k8s-triage-snapshot.sh --context kind-sre-demo -n demo -o "$SNAP"
done: /tmp/tmp.xR3jjK38BN (2 unhealthy pods captured, max 20; 0 sections failed)
```

Both pods unhealthy this time (example 1 captured 1), because both really were down.

## The diagnosis the skill actually produced

```text
Triage note — context kind-sre-demo, namespace demo, deployment/web:
- Finding: revision 2 ("v2: new entrypoint") is crash-looping. Both pods, Exit Code 1,
  Reason Error, Warning/BackOff events.
- No OOMKilled, no image-pull error, no probe failures (no readiness probe defined).
- Logs: "FATAL: config file not found".
- Cause: the v2 container command fails at start — wrong command / missing config.
- Impact: desired=2, ready=0 — worse than a readiness-probed rollout, because nothing
  gated the rollout: both old pods were replaced by the bad revision before either new
  pod proved healthy. Nothing is serving.
- Ownership: Pod -> ReplicaSet/web-664b48bf8f -> Deployment/web. No PDB, no HPA, no GitOps.
- Proposed: roll back deployment/web to revision 1. That's a write -> sre-k8s-safe-remediation.
```

The agent then stopped and told the human: *"Per the gate, I stop here — no write yet. Want me to continue into the actual approval-gated rollback live... so we get the full real transcript end-to-end for the doc?"*

## The hard stop at the skill boundary

The human said yes. The agent tried to chain straight into the remediation skill the same way:

```
Skill(sre-k8s-safe-remediation, "Roll back deployment/web ...")
```

```text
Error: Skill sre-k8s-safe-remediation cannot be used with Skill tool due to
disable-model-invocation. Ask the user to run /sre-k8s-safe-remediation
themselves — it cannot be invoked via the Skill tool. Do not replicate this
skill's workflow by other means — it is reserved for explicit user invocation.
```

This is `AGENTS.md`'s "manual only" rule enforced by the tool layer, not by the model choosing to comply. The agent could not route around it — it told the human to type the command themselves, and stopped:

> That skill is manual-only by design — I can't invoke it myself even with your approval. You need to run it directly. Please type: `/sre-k8s-safe-remediation` ...

The human then ran `/sre-k8s-safe-remediation` directly, which is how `sre-k8s-safe-remediation` actually entered context.

## The real remediation run

**1. Pin the target** — reused from the triage step, confirmed again:

```console
$ kubectl config get-contexts kind-sre-demo
CURRENT   NAME            CLUSTER         AUTHINFO        NAMESPACE
*         kind-sre-demo   kind-sre-demo   kind-sre-demo
```

**2. Evidence** — reused the triage snapshot (`tmp.xR3jjK38BN`, under a minute old) instead of recapturing it, per the skill's own "cite and reuse" rule.

**3. Ownership check** — a real miss surfaced here: `helm` isn't installed on this host.

```console
$ kubectl --context kind-sre-demo -n demo get deployment/web -o jsonpath='{.metadata.labels}{"\n"}{.metadata.annotations}{"\n"}'
{"app":"web"}
{"deployment.kubernetes.io/revision":"2","kubernetes.io/change-cause":"v2: new entrypoint"}
$ kubectl --context kind-sre-demo get hpa -n demo
No resources found in demo namespace.
$ helm --kube-context kind-sre-demo -n demo list
command not found: helm
```

No GitOps labels, no HPA. The Helm check failed on tooling, not on findings — this Deployment was created with plain `kubectl create deployment`, so there's no Helm release regardless. The run proceeded on that basis rather than stopping, since the object's own creation history already answers the ownership question.

**4. Preview, then propose:**

```console
$ kubectl --context kind-sre-demo -n demo rollout undo deployment/web --to-revision=1 --dry-run=server
deployment.apps/web rolled back (server dry run)
$ diff <(kubectl --context kind-sre-demo -n demo rollout history deployment/web --revision=2) \
       <(kubectl --context kind-sre-demo -n demo rollout history deployment/web --revision=1)
1c1
< deployment.apps/web with revision #2
---
> deployment.apps/web with revision #1
4,5c4,5
< 	pod-template-hash=664b48bf8f
<   Annotations:	kubernetes.io/change-cause: v2: new entrypoint
---
> 	pod-template-hash=557577df75
>   Annotations:	kubernetes.io/change-cause: v1: nginx 1.27
11,14d10
<     Command:
<       sh
<       -c
<       echo loading config /etc/web/app.conf; echo FATAL: config file not found >&2; exit 1
```

```text
Proposed action (NOT RUN):
  Command:     kubectl --context kind-sre-demo -n demo rollout undo deployment/web --to-revision=1
  Target:      context kind-sre-demo, namespace demo, deployment/web
  Evidence:    Exit Code 1 / BackOff, log "FATAL: config file not found"; triage snapshot tmp.xR3jjK38BN
  Ownership:   plain Deployment, no GitOps, no HPA, no Helm — safe to roll back directly
  Preview:     dry-run=server accepted; template returns to rev 1 (no command override)
  Risk:        med (sre-remediation-actions catalog)    Reversible: yes
  Expected:    rev 2 ReplicaSet scaled to 0, 2/2 v1 pods Ready, no new BackOff events
  Rollback:    kubectl --context kind-sre-demo -n demo rollout undo deployment/web --to-revision=2
>>> APPROVAL REQUIRED. Waiting for your explicit approval of this exact command. <<<
```

## The approval

The human's exact reply, verbatim, was the only thing that unblocked the next command:

> approved, run it

## Executed and verified

```console
$ kubectl --context kind-sre-demo -n demo rollout undo deployment/web --to-revision=1
deployment.apps/web rolled back
$ kubectl --context kind-sre-demo -n demo rollout status deployment/web --timeout=120s
deployment "web" successfully rolled out
$ kubectl --context kind-sre-demo -n demo events --for deployment/web | tail -n 50
LAST SEEN   TYPE     REASON              OBJECT           MESSAGE
2m45s       Normal   ScalingReplicaSet   Deployment/web   Scaled up replica set web-557577df75 from 0 to 2
2m22s       Normal   ScalingReplicaSet   Deployment/web   Scaled up replica set web-664b48bf8f from 0 to 1
2m21s       Normal   ScalingReplicaSet   Deployment/web   Scaled down replica set web-557577df75 from 2 to 1
2m21s       Normal   ScalingReplicaSet   Deployment/web   Scaled up replica set web-664b48bf8f from 1 to 2
2m21s       Normal   ScalingReplicaSet   Deployment/web   Scaled down replica set web-557577df75 from 1 to 0
5s          Normal   ScalingReplicaSet   Deployment/web   Scaled up replica set web-557577df75 from 0 to 1
4s          Normal   ScalingReplicaSet   Deployment/web   Scaled down replica set web-664b48bf8f from 2 to 1
4s          Normal   ScalingReplicaSet   Deployment/web   Scaled up replica set web-557577df75 from 1 to 2
4s          Normal   ScalingReplicaSet   Deployment/web   Scaled down replica set web-664b48bf8f from 1 to 0
$ kubectl --context kind-sre-demo -n demo get pods
NAME                   READY   STATUS    RESTARTS   AGE
web-557577df75-9r65n   1/1     Running   0          5s
web-557577df75-hwl4z   1/1     Running   0          4s
$ kubectl --context kind-sre-demo -n demo get rs -l app=web
NAME             DESIRED   CURRENT   READY   AGE
web-557577df75   2         2         2       2m45s
web-664b48bf8f   0         0         0       2m22s
$ kubectl --context kind-sre-demo -n demo rollout history deployment/web
REVISION  CHANGE-CAUSE
2         v2: new entrypoint
3         v1: nginx 1.27
```

2/2 Running, 0 restarts, bad ReplicaSet at 0. Revision 1's spec came back as revision 3 — a rollback always creates a new revision, it doesn't travel back in time.

## Cleanup

```console
$ kind delete cluster --name sre-demo
$ rm -rf "$SNAP"
$ rm -f "$KUBECONFIG"; unset KUBECONFIG
```

## What to take from this one specifically

- The manual-only gate on `sre-k8s-safe-remediation` is real and held even when the diagnosing skill itself proposed the write and the human had already said "yes, continue." The agent asked and then still couldn't comply — it had to hand the human the exact slash command instead.
- A tooling gap (missing `kind load` success, missing `helm` binary) didn't block the walkthrough and didn't get silently papered over — both are shown as they actually happened.
- Fixing the same bug on a Deployment with no readiness probe is strictly worse than example 1's version: you lose both replicas, not one. That's not a scripted detail — it's what this exact cluster did.
- Compare directly against [example 1](01-k8s-crashloop-rollback.md): same root cause, same two skills, same two approval gates — different blast radius, because this run didn't engineer the timing for a tidier before/after.
