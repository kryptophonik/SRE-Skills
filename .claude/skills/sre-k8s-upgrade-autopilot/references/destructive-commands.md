# Commands this skill never runs

These commands are listed so that nobody runs them by accident. The skill doesn't put them in a plan, even with approval. If an operator decides one is needed, they run it themselves after weighing the risk with the workload owner.

| Command | Why it's excluded | What the skill does instead |
| --- | --- | --- |
| `kubectl --context <ctx> drain <node> --disable-eviction` | Deletes pods directly, bypassing every PodDisruptionBudget. | Stops and reports the blocking PDB. The owner adds capacity or changes the PDB. |
| `kubectl --context <ctx> drain <node> --force --delete-emptydir-data` on an unreviewed node | Deletes bare pods for good and wipes emptyDir data. | Lists bare pods and emptyDir users in the preflight so owners move them first. |
| `kubectl --context <ctx> -n <ns> delete pdb <name>` | Takes away the workload's availability guarantee, often without its owner knowing. | Stop rule: a PDB that blocks a drain stops the plan. |
| `kubectl --context <ctx> delete validatingwebhookconfiguration <name>` or the mutating equivalent | Removes admission policy (security or data integrity) for the whole cluster. | Reports webhooks with `failurePolicy: Fail` and no ready backend. The owner fixes the backend. |
| `kubectl --context <ctx> patch ... -p '{"metadata":{"finalizers":null}}'` | Skips cleanup that a controller relies on, which can leave cloud resources orphaned. | Escalates to the controller's owner. |
| `aws eks update-cluster-version --name <cluster> --region <region> --kubernetes-version 1.<T> --force` | Skips the upgrade-readiness checks that EKS runs. | Fixes the insight that blocked the update. |
| `aws eks update-nodegroup-version --cluster-name <cluster> --nodegroup-name <ng> --region <region> --force` | Evicts pods even when a PDB forbids it. | Stops on a PodEvictionFailure and reports the PDB. |
| `aws eks update-cluster-config --name <cluster> --region <region> --upgrade-policy supportType=STANDARD` | Lets EKS upgrade the cluster automatically at the end of standard support instead of entering extended support. | Reports the policy and the dates. The decision stays with the owner. |
| `az aks upgrade --subscription <sub> --resource-group <rg> --name <cluster> --kubernetes-version <version> --enable-force-upgrade` | Skips the check for APIs removed in the target, so clients start failing after the upgrade. | Removed-API use is a stop rule. Fix the clients first. |
| `az aks upgrade --subscription <sub> --resource-group <rg> --name <cluster> --kubernetes-version <version>` (without `--control-plane-only`) | Upgrades the control plane and every node pool in one operation, with no verification between pools. | Control plane only, then one pool at a time. |
| `gcloud beta container clusters complete-control-plane-upgrade <cluster> --project <project> --location <location>` | Ends the soak of a two-step upgrade early and with it the only way to roll the control-plane minor back. | Lets the soak run, and verifies during it. |
