# CI/CD and GitOps Handoff Verification — 2026-09-16

## Goal

The last missing part of the CI/CD flow was to connect the image publishing workflow with the GitOps deployment flow.

Before this work, GitHub Actions already:

- ran application and platform validation
- authenticated to Azure with GitHub OIDC
- built the four NordicShop images
- pushed them to ACR
- collected the immutable image digests

But after collecting the digests, the workflow stopped.

The missing part was:

```text
ACR image digests
-> update Helm values
-> create pull request
-> review and merge
-> Argo CD deploys the change
```

## What was changed

I updated:

```text
.github/workflows/publish-images.yml
```

The workflow now does the following after publishing the images:

1. gets the immutable SHA256 digest for each image
2. updates the four image references in `helm/nordicshop/values-dev.yaml`
3. runs Helm validation
4. creates a temporary automation branch
5. commits only the updated Helm values file
6. pushes the branch
7. creates a pull request against `main`

The workflow does not merge the pull request automatically.

The merge is still done manually so the deployment has a review step.

## Workflow permissions

The final workflow permissions are:

```yaml
permissions:
  contents: write
  pull-requests: write
  id-token: write
```

`id-token: write` is used for Azure OIDC.

`contents: write` is used to push the automation branch.

`pull-requests: write` is used to create the pull request.

No GitHub PAT or Azure client secret was added.

## First test

The first real workflow test completed almost everything successfully:

```text
build images
push images to ACR
capture digests
update Helm values
Helm lint
Helm template
create branch
push branch
```

The last step failed because GitHub Actions was not allowed to create pull requests.

The error was:

```text
GitHub Actions is not permitted to create or approve pull requests
```

I fixed this under:

```text
Repository Settings
-> Actions
-> General
-> Workflow permissions
```

and enabled:

```text
Allow GitHub Actions to create and approve pull requests
```

The workflow itself still only creates the PR. It does not approve or merge it.

## Successful workflow test

After fixing the GitHub permission, I ran the image publishing workflow again.

The workflow completed successfully and automatically created:

```text
PR #3
chore: update NordicShop image digests
```

The PR changed only:

```text
helm/nordicshop/values-dev.yaml
```

The four new immutable image digests were:

```text
Nordic API
sha256:c3000dfcbcb83fc5a2c27a17abad81336aa8724a82d0764aca472dc30ca06b19

Customer Web
sha256:baea2c9898031ca42a991281468799311016a9699805abf4edfafa342e73d058

Vendor Portal
sha256:7457c7c622dea7f414eeafa9dca7081ec4951837fefe40501d1bcb834670d95a

Admin Portal
sha256:330f1acb1a97315bc0e88051e400ab98a98aa6c7fd17ec38676b4e6e1854f48d
```

The workflow also ran `helm lint` and `helm template` before opening the PR.

## Pull request merge

I reviewed PR #3 and merged it manually into `main`.

The merged Git revision was:

```text
f867a74509d4e4a20ea4325c949447eb204590a1
```

I did not run `helm upgrade`, `kubectl apply` or `kubectl set image` after the merge.

This was important because I wanted to verify that Argo CD was really doing the deployment from Git.

## Argo CD verification

Argo CD detected the new `main` revision automatically.

The sync history showed that the deployment was started automatically.

The sync completed successfully:

```text
successfully synced (all tasks run)
```

Final Argo CD state:

```text
Synced
Healthy
f867a74509d4e4a20ea4325c949447eb204590a1
```

This confirms that Argo CD detected the reviewed Git change and reconciled AKS automatically.

## AKS verification

After the Argo CD sync, all NordicShop Pods were healthy.

Final main workload state:

```text
Admin Portal      1/1 Running
Nordic API        2/2 Running
Customer Web      1/1 Running
Vendor Portal     1/1 Running
PostgreSQL        1/1 Running
Redis             1/1 Running
```

The four custom Deployments were using the new immutable image digests.

Nordic API:

```text
acrnordicshopazaddevweu.azurecr.io/nordicshop-api@sha256:c3000dfcbcb83fc5a2c27a17abad81336aa8724a82d0764aca472dc30ca06b19
```

Customer Web:

```text
acrnordicshopazaddevweu.azurecr.io/nordicshop-customer-web@sha256:baea2c9898031ca42a991281468799311016a9699805abf4edfafa342e73d058
```

Vendor Portal:

```text
acrnordicshopazaddevweu.azurecr.io/nordicshop-vendor-portal@sha256:7457c7c622dea7f414eeafa9dca7081ec4951837fefe40501d1bcb834670d95a
```

Admin Portal:

```text
acrnordicshopazaddevweu.azurecr.io/nordicshop-admin-portal@sha256:330f1acb1a97315bc0e88051e400ab98a98aa6c7fd17ec38676b4e6e1854f48d
```

## HPA check

The Nordic API HPA was still working correctly.

Final state:

```text
Min replicas: 2
Max replicas: 4
CPU target: 70%
Current replicas: 2
Current CPU: 3%
```

The HPA was able to read valid CPU metrics.

Some temporary metric warnings appeared while the new API Pods were becoming ready, but the final HPA state was healthy and no change was required.

## Final verified flow

The complete deployment flow is now:

```text
code change
-> CI validation
-> Publish Images workflow
-> GitHub OIDC
-> build images
-> push images to ACR
-> collect immutable digests
-> update values-dev.yaml
-> Helm validation
-> create digest-update PR
-> manual review and merge
-> Argo CD detects main
-> AKS updates automatically
-> application becomes Synced and Healthy
```

## Final result

```text
CI validation                         PASS
GitHub OIDC                           PASS
ACR image publishing                  PASS
Immutable digest capture              PASS
Automatic Helm digest update          PASS
Automatic PR creation                 PASS
Human review before deployment        PASS
Argo CD automatic sync                PASS
AKS image rollout                     PASS
Nordic API 2 replicas                 PASS
HPA working                           PASS
Final Argo state Synced               PASS
Final Argo state Healthy              PASS
Git remains deployment authority      PASS
```

## Conclusion

The remaining CI/CD handoff is now complete.

Publishing an image to ACR does not directly deploy it to AKS.

The new digest must first be written into Git through a pull request.

After the PR is reviewed and merged, Argo CD detects the Git change and deploys it automatically.

The final deployment authority is now:

```text
Git
-> Argo CD
-> AKS
```

The next project phase is application observability and alerts.
