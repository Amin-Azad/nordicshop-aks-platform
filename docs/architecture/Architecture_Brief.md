# NordicShop Azure / AKS Architecture Brief

## 1. Scope and goals

NordicShop is a small multi-tenant shopping platform used to learn and prove Azure, AKS, Terraform, Kubernetes, Helm, identity, GitOps, monitoring and recovery.

The application has six main workloads:

1. Customer Web
2. Vendor Portal
3. Admin Portal
4. Nordic API
5. PostgreSQL
6. Redis

The application is intentionally small. The main goal is not to build a full e-commerce product. The goal is to build and operate a believable cloud platform around it.

The platform should be simple enough to understand and explain, but realistic enough for a portfolio project.

---

## 2. Full platform architecture

The main request path is:

```text
Internet
   ↓
Public IP / Azure Load Balancer
   ↓
AKS Gateway / HTTPRoute
   ↓
Customer Web / Vendor Portal / Admin Portal
   ↓
Nordic API
   ↓
PostgreSQL / Redis
```

Around the application, Azure provides the main platform services:

```text
Azure Resource Group
├── VNet
├── AKS
├── ACR
├── Key Vault
├── Managed Identities
├── Azure RBAC
├── Log Analytics / Azure Monitor
├── diagnostics
└── budget controls
```

GitHub and GitHub Actions are outside the AKS workload path.

Terraform remote state is also kept separately in:

```text
rg-tfstate-nordicshop-weu
└── stnstf242817791
    └── tfstate
        └── dev.terraform.tfstate
```

This keeps Terraform state separate from the NordicShop workload resource group.

---

## 3. Request flow

A customer request should follow this path:

```text
Customer Browser
   ↓
Public DNS / HTTPS
   ↓
Public IP / Azure Load Balancer
   ↓
AKS Gateway / HTTPRoute
   ↓
Customer Web Service
   ↓
Customer Web Pod
   ↓
/api/*
   ↓
Nordic API Service
   ↓
Nordic API Pod
   ↓
PostgreSQL or Redis
```

Vendor and Admin traffic follow the same pattern, but their frontend routes go to the Vendor Portal and Admin Portal.

Public traffic should only reach the intended web and API entry points.

PostgreSQL and Redis must not be directly public.

Inside AKS, Services and Kubernetes DNS are used instead of Pod IP addresses.

Examples:

```text
nordic-api
postgres
redis
```

The exact service names will come from the Helm chart.

---

## 4. CI/CD and GitOps flow

The deployment flow is:

```text
Developer
   ↓
GitHub
   ↓
GitHub Actions
   ↓
OIDC authentication to Microsoft Entra ID
   ↓
build / test / scan
   ↓
Azure Container Registry
   ↓
image digest is written into Helm values
   ↓
Git change is reviewed and merged
   ↓
Argo CD sees the Git change
   ↓
NordicShop Helm Release
   ↓
AKS workloads are reconciled
```

GitHub Actions builds and pushes images.

Argo CD does not watch ACR directly.

Argo CD watches Git and makes the cluster match the desired state stored in Git.

The Helm values should use immutable image digests instead of only tags.

---

## 5. Identity architecture

NordicShop should not use one identity for everything.

Different actions use different identities.

### Local Terraform identity

Used when I run Terraform from my own machine.

It authenticates to Azure and can create or update the infrastructure I am allowed to manage.

### GitHub Actions identity

GitHub Actions authenticates to Microsoft Entra ID using OIDC.

It should not use a stored Azure client secret.

It needs only the permissions required for CI/CD and infrastructure tasks.

### AKS cluster identity

Used by AKS for control-plane related Azure operations.

It should not be used by application workloads.

### Kubelet identity

Used by AKS nodes when pulling container images.

Main role:

```text
AcrPull
```

on the NordicShop ACR.

### Application workload identities

The Nordic API and database administration paths use separate identities.

```text
Nordic API Pod
   ↓
ServiceAccount: nordic-api
   ↓
Nordic API managed identity
   ↓
Key Vault secret: nordicshop-app-database-url
```

```text
PostgreSQL / database security Job
   ↓
ServiceAccount: nordicshop-db-admin
   ↓
DB-admin managed identity
   ↓
Key Vault secrets:
postgres-password
postgres-app-password
```

Both identities use AKS OIDC federation. Key Vault RBAC is scoped to the individual secrets each identity needs, so the API does not receive the PostgreSQL superuser password.

### Argo CD identity

Argo CD runs inside Kubernetes and reconciles Kubernetes resources.

It should not automatically receive broad Azure permissions.

---

## 6. Network design

NordicShop uses one Azure VNet for the development platform.

The basic structure is:

```text
VNet
├── AKS subnet
└── Reserved / future Private Endpoint subnet
```

The AKS subnet is used by the AKS nodes.

The private endpoint subnet is reserved for future use so we can add Private Link later without redesigning the whole network.

For the current portfolio scope, Key Vault can use its normal Azure endpoint with proper identity and access control.

Private Link can be added later as a production-style improvement.

ACR also does not need Private Link for the first version.

Inside AKS:

```text
Gateway / HTTPRoute
Services
Pods
NetworkPolicy templates
```

The current development cluster uses Gateway API for routing. NetworkPolicy templates are present in the Helm chart, but enforcement remains disabled until the planned Cilium migration is completed safely.

Azure networking controls the larger cloud network path.

PostgreSQL and Redis remain internal services.

---

## 7. PostgreSQL and Redis

PostgreSQL and Redis intentionally stay inside AKS for this project.

This is mainly for learning.

### PostgreSQL

PostgreSQL runs as:

```text
StatefulSet
   ↓
PVC
   ↓
Azure-backed persistent storage
```

If the PostgreSQL Pod dies, Kubernetes should recreate it.

The PVC should remain.

If the node dies, Kubernetes can move the workload and attach the persistent disk again, depending on the storage setup.

Terraform manages the Azure infrastructure that makes AKS and storage possible.

Helm manages the PostgreSQL StatefulSet, Service and PVC definition.

### Redis

Redis runs as a normal Kubernetes Deployment.

It is used for cart and temporary state.

Redis is allowed to be more replaceable than PostgreSQL.

For a serious production marketplace, I would evaluate:

```text
Azure Database for PostgreSQL
managed Redis service
```

instead of self-managing both inside Kubernetes.

---

## 8. Ownership boundaries

The ownership split is:

### Terraform

Terraform manages Azure infrastructure.

```text
Resource Group
VNet
Subnets
AKS
ACR
Key Vault
Managed Identities
Azure RBAC
Federated Identity Credentials
Log Analytics
Azure Monitor foundation
Diagnostic Settings
Budget controls
```

### Helm

Helm manages Kubernetes application objects.

```text
Deployments
Services
StatefulSet
PVC
ConfigMaps
ServiceAccounts
Gateway / HTTPRoute
NetworkPolicy templates
HPA
probes
resource requests and limits
```

### Argo CD

Argo CD keeps the Kubernetes cluster matching the desired Helm configuration stored in Git.

Terraform should not manage every application-level Kubernetes object because Terraform is being used for the Azure platform layer, while Helm and Argo CD are better suited to the Kubernetes application layer.

---

## 9. Cost decisions

NordicShop is a portfolio project, not a commercial production platform.

The main cost goals are:

```text
low cost
bounded cost
easy to deploy
easy to destroy
no unnecessary enterprise services
```

The project should still look realistic.

Examples of intentional simplifications:

```text
public AKS entry instead of a fully private platform
in-cluster PostgreSQL for learning
in-cluster Redis
reserved Private Endpoint subnet, but no Private Link initially
simple monitoring first
managed Prometheus / Grafana only if cost is acceptable
small node pools
```

A serious production platform would likely add stronger private networking, managed databases, more redundancy and more monitoring.

For NordicShop, the simpler design is intentional.

---

## 10. Failure boundaries

The main failures we want to understand are:

### Invalid API image

Detected by:

```text
Kubernetes rollout status
Pod events
readiness failure
Argo CD health
monitoring alerts
```

Recovery:

```text
Git revert
→ Argo CD reconciliation
```

### PostgreSQL Pod failure

Detected by:

```text
Pod state
API readiness
database connectivity
```

Expected behavior:

```text
Pod is recreated
PVC remains
data should still exist
```

### Redis failure

Detected by:

```text
Redis Pod state
API dependency checks
cart behavior
```

Expected behavior:

```text
temporary cart/cache function degrades
Redis is restored
service recovers
```

### Cross-tenant API attempt

Detected by:

```text
API authorization logic
tenant ownership checks
PostgreSQL RLS
security tests
```

Expected result:

```text
request denied or not found
```

### Unauthorized Key Vault access

Detected by:

```text
Workload Identity failure
Azure RBAC denial
application logs
```

Expected result:

```text
unrelated Pod cannot read secrets
```

### GitHub OIDC failure

Detected by:

```text
GitHub Actions authentication failure
```

Expected result:

```text
workflow cannot access Azure
```

### ACR pull failure

Detected by:

```text
ImagePullBackOff
Pod events
```

Possible causes:

```text
wrong image
wrong digest
missing AcrPull
registry access issue
```

### Gateway or API failure

Detected by:

```text
HTTP errors
readiness checks
Gateway / HTTPRoute state
API logs
Azure Monitor
```

The goal is to identify which layer failed instead of treating every problem as an application problem.

---

## 11. Terraform implementation order

The platform was built in this dependency order:

```text
01. resource-group
02. network
03. monitoring
04. acr
05. identities
06. aks
07. rbac
08. key-vault
09. federation
10. diagnostics
11. budget
```

The important dependencies are:

```text
resource-group
   ↓
network
   ↓
AKS
```

```text
monitoring
   ↓
AKS
   ↓
diagnostics
```

```text
ACR
   ↓
RBAC
   ↑
kubelet identity
```

```text
AKS OIDC issuer
   +
Nordic API managed identity
   ↓
federated identity credential
   ↓
Workload Identity
```

```text
Nordic API / DB-admin managed identities
   ↓
secret-scoped Key Vault RBAC
   ↓
Key Vault
```


---

## 12. Final architecture rule

Before adding a new Azure resource, I should be able to answer:

```text
What problem does this resource solve?
Where does it sit in the architecture?
Which identity uses it?
Which network path reaches it?
What depends on it?
What does it cost?
What happens if it fails?
Who owns it: Terraform, Helm or Argo CD?
```

If I cannot answer these questions, I should understand the architecture first before adding the resource.
