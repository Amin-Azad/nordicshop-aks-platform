# AKS Helm Digest Deployment Evidence

Date: 2026-09-15

## Release

Helm release:
nordicshop

Namespace:
nordicshop

Helm revision:
13

Status:
deployed

Chart:
nordicshop-0.1.0

## Deployment result

The existing NordicShop Helm release was upgraded from mutable v1/v2 image tags to immutable ACR digest references using:

helm/nordicshop/values-dev.yaml

The upgrade was performed with:

- --wait
- --atomic
- --timeout 5m

## Running custom images

Nordic API:
acrnordicshopazaddevweu.azurecr.io/nordicshop-api@sha256:f8c6840f14c3eef15dcad1631f5df9773c71d510859ab0d3038a1c7235973b11

Customer Web:
acrnordicshopazaddevweu.azurecr.io/nordicshop-customer-web@sha256:97f563471d579b10221330598f574838a90244dadc3293a97053986ae1297fd8

Vendor Portal:
acrnordicshopazaddevweu.azurecr.io/nordicshop-vendor-portal@sha256:e5d83ad04b6708c23316fe1ab20dc5776dd0d4d15d3b27377582b9f749bf1c57

Admin Portal:
acrnordicshopazaddevweu.azurecr.io/nordicshop-admin-portal@sha256:d38a82339945931f1733073031a1c19f45112f6d08ebc959c9e5ea2ea44fa080

## Runtime verification

All four Deployments successfully rolled out.

The Kubernetes Deployment image references matched the intended Helm digest values.

The running Pod container imageID values also matched the same ACR digests.

All NordicShop application Pods were Running and Ready.

## Functional verification

The following entry paths were manually verified and behaved as expected:

- Customer Web
- Vendor Portal
- Admin Portal
- /api/products

## Important boundary

No Argo CD deployment was introduced.

This was a manual Helm upgrade to verify the real AKS release path before GitOps.
