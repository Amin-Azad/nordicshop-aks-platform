# NordicShop AKS Workload Identity and Key Vault Verification

## Scope

This stage migrated NordicShop runtime database secrets from Helm-managed Kubernetes Secrets to Azure Key Vault using AKS Workload Identity and the Secrets Store CSI Driver.

## Azure configuration

- AKS OIDC issuer enabled
- AKS Workload Identity enabled
- Azure Key Vault Secrets Provider enabled
- Secret rotation enabled
- User-assigned managed identity used by Nordic API
- Federated identity credential configured for:
  - namespace: `nordicshop`
  - service account: `nordic-api`
- Managed identity has `Key Vault Secrets User` scoped to the NordicShop Key Vault

## Kubernetes configuration

The Nordic API uses:

- ServiceAccount: `nordic-api`
- Workload Identity pod label
- Secrets Store CSI volume
- SecretProviderClass: `nordicshop-keyvault`

Key Vault secrets are synchronized into:

`nordicshop-runtime-secret`

The synchronized secret contains the runtime database configuration required by:

- NordicShop API
- PostgreSQL StatefulSet

The previous Helm-managed `nordicshop-secret` was removed.

## Secret handling

The Helm chart no longer requires `values-local-secret.yaml`.

No production/runtime database password is stored in:

- Helm values
- tracked Kubernetes manifests
- Terraform variables
- Git

Local Docker Compose credentials were also changed to environment-variable based configuration instead of committed plaintext credentials.

## Credential rotation

The PostgreSQL credential was rotated after the original development credential was found in historical local development configuration.

Verification included:

1. Updating the PostgreSQL role password.
2. Updating Key Vault secret `postgres-password`.
3. Updating Key Vault secret `nordicshop-database-url`.
4. Verifying CSI rotation synchronized both values.
5. Restarting the API.
6. Restarting PostgreSQL.
7. Confirming API-to-PostgreSQL queries still succeeded.

No PostgreSQL PVC was deleted.

## Persistence verification

PostgreSQL StatefulSet was restarted after credential rotation.

Verified:

- `postgres-0` returned to `1/1 Running`
- `postgres-pvc` remained `Bound`
- existing application data remained available
- `/api/products` returned the seeded product data successfully

## Workload Identity isolation test

A temporary Pod using the namespace `default` ServiceAccount attempted to mount the same Key Vault SecretProviderClass.

The mount failed with Azure authentication error:

`AADSTS700213`

Azure reported that no matching federated identity record existed for:

`system:serviceaccount:nordicshop:default`

This confirms that the Nordic API federated identity cannot be used by unrelated ServiceAccounts.

The test Pod was deleted after verification.

## RBAC cleanup

Temporary human `Key Vault Secrets Officer` access used during secret creation and rotation was removed.

The Nordic API managed identity retained only:

`Key Vault Secrets User`

for application runtime secret access.

## Helm verification

Helm validation completed successfully without any local secret values file.

Result:

`1 chart(s) linted, 0 chart(s) failed`

The old `nordicshop-secret` is no longer rendered or present in the cluster.

## Terraform verification

Terraform validation succeeded.

Final plan result:

`No changes. Your infrastructure matches the configuration.`

This confirms the Azure environment matches the committed Terraform configuration.

## Final result

NordicShop now uses:

Azure Key Vault
→ AKS Workload Identity
→ Nordic API managed identity
→ Secrets Store CSI Driver
→ `nordicshop-runtime-secret`
→ API and PostgreSQL

The solution provides:

- no committed runtime database credentials
- workload-specific Azure authentication
- Key Vault-backed secret storage
- automatic CSI secret synchronization
- least-privilege Key Vault access
- PostgreSQL data persistence
- verified denial for unrelated Kubernetes ServiceAccounts
