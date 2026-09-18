# NordicShop Managed Observability and Alerting Verification

Date: 2026-09-18

## Scope

This verification covers the NordicShop AKS monitoring and alerting setup using Azure Managed Prometheus, Azure Managed Grafana, Azure Monitor Prometheus alert rules, and Azure Monitor Action Groups.

## Managed Prometheus

Azure Monitor Workspace:

- amw-nordicshop-dev-weu

Managed Prometheus successfully collects:

- NordicShop API application metrics
- Kubernetes workload metrics
- Argo CD application metrics

The NordicShop API exposes Prometheus metrics including:

- HTTP request count
- HTTP request duration
- HTTP status codes
- API target availability

Argo CD metrics are also scraped through the Azure Monitor managed Prometheus collector.

## Managed Grafana

Azure Managed Grafana:

- amg-nordicshop-dev-weu

Three dashboards were created and verified:

1. NordicShop Application / Marketplace
2. NordicShop Kubernetes / Namespace Health
3. NordicShop GitOps / Delivery

The dashboards successfully display live data from the Azure Monitor Workspace.

## Prometheus Alert Rules

Prometheus rule group:

- amprg-nordicshop-dev-weu

The following alert rules are enabled:

- NordicShopAPIUnavailable
- NordicShopReplicaAvailabilityDegraded
- NordicShopArgoCDUnhealthy
- NordicShopHigh5xxErrorRate

The rule group evaluates every minute.

Each alert condition must remain active for five minutes before firing.

## Alert Notifications

Azure Monitor Action Group:

- ag-nordicshop-dev-weu

The Action Group contains a verified email receiver.

A direct Action Group notification test completed successfully and the test email was received.

## Real Alert Test

A real alert test was performed by temporarily disabling Argo CD automated reconciliation and scaling the NordicShop API deployment to zero replicas.

This caused the Argo CD Application to move away from its Git-defined state.

The following alert successfully fired:

- NordicShopArgoCDUnhealthy
- Severity: Warning
- Monitor service: Prometheus

Azure Monitor confirmed that the alert condition remained satisfied for more than five minutes.

This verified the complete alert path:

Prometheus metric
→ Azure Managed Prometheus
→ Prometheus alert rule
→ Azure Monitor alert
→ Action Group
→ Email notification

## Recovery Verification

After the alert test:

- NordicShop API was restored to 2 replicas
- API deployment returned to 2/2 Ready
- Argo CD automated sync was re-enabled
- Argo CD self-heal was re-enabled
- Argo CD returned to Synced / Healthy

## Terraform Verification

A final Terraform plan was executed after recovery.

Result:

```text
No changes. Your infrastructure matches the configuration.
