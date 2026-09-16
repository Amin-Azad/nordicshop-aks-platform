# Argo CD / GitOps Verification — 2026-09-16

## Goal

Verify that NordicShop is managed through GitOps using Argo CD, with Git as the deployment source of truth.

## Final design

Argo CD is installed in the `argocd` namespace.

The NordicShop Argo CD `Application` watches:

- Repository: `Amin-Azad/nordicshop-aks-platform`
- Branch: `main`
- Helm chart: `helm/nordicshop`
- Values file: `values-dev.yaml`
- Destination namespace: `nordicshop`

The final sync policy enables automated sync, `selfHeal: true`, `prune: true`, `PruneLast=true`, and retry with exponential backoff. `CreateNamespace=false` is used because the `nordicshop` namespace already exists and is not created by Argo CD.

## Bootstrap verification

The Argo CD installation is kept in Git under:

```text
gitops/argocd/
├── application.yaml
└── install/
    ├── kustomization.yaml
    └── namespace.yaml
```

The install is pinned to Argo CD `v3.5.3`.

The upstream Argo CD manifest is rendered through Kustomize and installed with server-side apply. Server-side apply was required because the `applicationsets.argoproj.io` CRD exceeded the normal client-side apply annotation size limit.

During the first bootstrap, the namespaced Argo CD resources were accidentally created in the `default` namespace because the Kustomization did not yet contain `namespace: argocd`. The Kustomization was corrected, Argo CD was installed successfully in `argocd`, and the accidental namespaced resources were removed from `default` without deleting the shared CRDs or cluster RBAC.

Final Argo CD runtime state showed all main components healthy:

```text
argocd-application-controller      Running
argocd-applicationset-controller  Running
argocd-dex-server                 Running
argocd-notifications-controller   Running
argocd-redis                      Running
argocd-repo-server                Running
argocd-server                     Running
```

The Argo CD CRDs were present:

```text
applications.argoproj.io
applicationsets.argoproj.io
appprojects.argoproj.io
```

## First NordicShop adoption

Before the first Argo CD sync:

- the existing Helm release was healthy at revision 15
- `kubectl diff` between the live cluster and the rendered Helm manifests returned no material differences
- Argo CD reported the Application as `OutOfSync` but `Healthy`
- the existing workloads did not yet contain Argo CD tracking metadata

The first manual sync was pinned to Git revision:

```text
e909a38037617ca0009bebcb9d3b2bf332157bdd
```

The operation completed successfully:

```text
Sync Status:   Synced
Health Status: Healthy
Operation:     successfully synced (all tasks run)
```

After adoption, the API Deployment contained the Argo CD tracking ID:

```text
nordicshop:apps/Deployment:nordicshop/nordicshop-api
```

The NordicShop workloads remained healthy during the ownership transition.

## Final Argo CD application configuration

The final Argo CD configuration was committed and pushed in commit:

```text
06b3ec9 — add Argo CD GitOps configuration
```

Argo CD reconciled to that Git revision and remained `Synced` and `Healthy`.

## Automatic sync test

A harmless annotation was added to the API Deployment Helm template:

```text
gitops.nordicshop/test: auto-sync-v1
```

The change was committed and pushed to Git only. No `kubectl apply` or `helm upgrade` was run.

Argo CD detected the Git change and automatically applied it to AKS.

Verification from the live API Deployment returned:

```text
auto-sync-v1
```

Automatic sync: **PASS**

## Self-heal test

The live API Deployment annotation was manually changed with `kubectl` to:

```text
manual-drift
```

Argo CD detected that the live cluster no longer matched Git and restored the Git value almost immediately.

Final live value:

```text
auto-sync-v1
```

The Argo CD Application remained `Synced` and `Healthy`.

Self-heal: **PASS**

## Prune test

A temporary ConfigMap named `gitops-prune-test` was added through Git. Argo CD created it automatically in the `nordicshop` namespace.

The ConfigMap template was then removed from Git and pushed in commit:

```text
20d44ed — verify Argo CD prune
```

No manual `kubectl delete` was used.

Final verification:

```text
Error from server (NotFound): configmaps "gitops-prune-test" not found
```

Prune: **PASS**

## Test cleanup

The temporary API annotation was removed from the Helm template and pushed in commit:

```text
ca5ec7b — remove GitOps verification annotation
```

Argo CD automatically removed the annotation from the live Deployment.

Final Application state:

```text
NAME         SYNC STATUS   HEALTH STATUS
nordicshop   Synced        Healthy
```

## Final result

```text
Argo CD installed in argocd namespace      PASS
Application Synced + Healthy               PASS
Git revision reconciliation                PASS
Helm values-dev.yaml source                PASS
Immutable custom image digests             PASS
Automatic sync                             PASS
Self-heal                                  PASS
Prune                                      PASS
NordicShop workloads healthy               PASS
Git is the deployment authority            PASS
```

The normal NordicShop deployment path is now:

```text
Git change
   -> GitHub main
   -> Argo CD detects new desired state
   -> Argo CD renders helm/nordicshop with values-dev.yaml
   -> Argo CD reconciles AKS
   -> NordicShop remains Synced and Healthy
```

Routine application deployment should now be performed through reviewed Git changes rather than manual `helm upgrade`, `kubectl apply`, `kubectl edit`, or `kubectl set image` commands.
