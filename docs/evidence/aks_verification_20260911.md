# NordicShop AKS Verification Evidence

**Date:** 2026-09-11  
**Environment:** dev  
**Region:** West Europe  
**Cluster:** `aks-nordicshop-dev-weu`

## Purpose

Record the successful creation, recovery, Terraform reconciliation, and runtime verification of the NordicShop AKS development cluster.

## Terraform result

The AKS module was created with:

- Kubernetes version: `1.36`
- Public AKS API server
- System-assigned AKS managed identity
- OIDC issuer enabled
- Workload Identity enabled
- Azure CNI Overlay
- Existing AKS subnet
- One system node pool
- Two `Standard_D4s_v4` nodes
- Existing Log Analytics workspace integration

Final Terraform reconciliation result:

```text
No changes. Your infrastructure matches the configuration.
```

## Network configuration

```text
VNet:                10.20.0.0/16
AKS subnet:          10.20.0.0/22
Reserved PE subnet:  10.20.4.0/24
Pod CIDR:            10.244.0.0/16
Service CIDR:        10.30.0.0/16
DNS service IP:      10.30.0.10
Network plugin:      Azure CNI
Network mode:        Overlay
Outbound type:       LoadBalancer
```

## AKS runtime verification

Azure reported:

```text
ProvisioningState: Succeeded
PowerState:        Running
KubernetesVersion: 1.36
```

Terraform exposed the expected AKS outputs:

```text
aks_name
aks_oidc_issuer_url
aks_cluster_identity_principal_id
aks_kubelet_identity_object_id
aks_node_resource_group
```

The generated AKS node resource group is:

```text
MC_rg-nordicshop-dev-weu_aks-nordicshop-dev-weu_westeurope
```

## Kubernetes verification

`kubectl` successfully connected to the AKS cluster.

Both nodes were Ready:

```text
aks-system-18907494-vmss000000   Ready   v1.36.3   10.20.0.5
aks-system-18907494-vmss000001   Ready   v1.36.3   10.20.0.4
```

Default namespaces were healthy:

```text
default
kube-node-lease
kube-public
kube-system
```

This proves that the AKS control plane is reachable and both worker nodes are successfully registered and operational.

## Identity boundaries

The platform keeps the following identities separate:

```text
Local Terraform identity
GitHub Actions identity                 (later)
AKS cluster managed identity
AKS kubelet managed identity
Nordic API user-assigned managed identity
```

No Azure RBAC assignments were added during the AKS phase.

`AcrPull`, Key Vault access, federated identity credentials, Kubernetes ServiceAccounts, Helm workloads, and Argo CD remain deliberately postponed.

## Issue encountered and recovery

The first AKS create operation failed because the Azure subscription was not registered for:

```text
Microsoft.OperationsManagement
```

The provider was registered and the AKS cluster was reconciled with:

```bash
az aks update   --resource-group rg-nordicshop-dev-weu   --name aks-nordicshop-dev-weu
```

Azure then reported:

```text
ProvisioningState: Succeeded
PowerState: Running
```

Because the AKS resource had been created in Azure before Terraform recorded it in state, it was imported into Terraform state.

After import, the node-pool upgrade settings were reconciled with the current Azure configuration.

Final result:

```text
No changes. Your infrastructure matches the configuration.
```

## AKS phase exit status

**AKS phase: COMPLETE**

Verified:

- AKS exists in Azure
- Terraform owns the AKS resource
- Remote Terraform state is healthy
- Two system nodes are Ready
- Kubernetes version is correct
- Azure CNI Overlay is configured correctly
- OIDC issuer is enabled
- Workload Identity is enabled
- Cluster and kubelet identities exist
- Log Analytics integration is enabled
- Terraform plan is clean
- `kubectl` connectivity works

## Next Terraform phase

```text
07 — Azure RBAC
```

The next phase will create least-privilege Azure role assignments, starting with the AKS kubelet identity receiving `AcrPull` on the existing Azure Container Registry.
