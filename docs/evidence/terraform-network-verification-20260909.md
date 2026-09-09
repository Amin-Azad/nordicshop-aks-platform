# Terraform Network Verification

Date: 2026-09-09

## Module

`infra/modules/network`

## Resources created

- VNet: `vnet-nordicshop-dev`
- VNet CIDR: `10.20.0.0/16`
- AKS subnet: `snet-aks`
- AKS subnet CIDR: `10.20.0.0/22`
- Reserved Private Endpoint subnet: `snet-private-endpoint`
- Reserved subnet CIDR: `10.20.4.0/24`

## Resource group

`rg-nordicshop-dev-weu`

## Terraform result

Initial deployment:

`3 added, 0 changed, 0 destroyed`

Final verification:

`No changes. Your infrastructure matches the configuration.`

## Azure verification

Azure CLI confirmed:

- VNet exists in West Europe
- VNet address space is correct
- AKS subnet exists
- Reserved Private Endpoint subnet exists

## Important learning

The resource group module exposes its name as an output.

The dev root passes that output to the network module:

`module.resource_group.name -> module.network.resource_group_name`

This creates the Terraform dependency automatically.

The AKS subnet ID is exposed from the network module so the future AKS module can use it.

The Private Endpoint subnet is reserved for future hardening only. No Private Endpoint is deployed in the current version.
