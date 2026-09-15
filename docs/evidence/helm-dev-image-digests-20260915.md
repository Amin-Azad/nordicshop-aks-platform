# Helm Dev Image Digest Validation

Date: 2026-09-15

## Change

Updated only:

helm/nordicshop/values-dev.yaml

The four NordicShop custom images now use immutable ACR digest references.

## Published source commit

8d2d103813bdfd921adadb0a1b3d7071730b8545

## Verified image references

- nordicshop-api
  acrnordicshopazaddevweu.azurecr.io/nordicshop-api@sha256:f8c6840f14c3eef15dcad1631f5df9773c71d510859ab0d3038a1c7235973b11

- nordicshop-customer-web
  acrnordicshopazaddevweu.azurecr.io/nordicshop-customer-web@sha256:97f563471d579b10221330598f574838a90244dadc3293a97053986ae1297fd8

- nordicshop-vendor-portal
  acrnordicshopazaddevweu.azurecr.io/nordicshop-vendor-portal@sha256:e5d83ad04b6708c23316fe1ab20dc5776dd0d4d15d3b27377582b9f749bf1c57

- nordicshop-admin-portal
  acrnordicshopazaddevweu.azurecr.io/nordicshop-admin-portal@sha256:d38a82339945931f1733073031a1c19f45112f6d08ebc959c9e5ea2ea44fa080

## Validation

helm lint:
1 chart(s) linted, 0 chart(s) failed

helm template:
Rendered successfully for namespace nordicshop.

Rendered manifest:
495 lines

Rendered ACR digest references:
4

Old NordicShop v1/v2 image references:
none found

Redis and PostgreSQL remain on their existing upstream image tags.

## Deployment status

No Helm install or upgrade was performed.
AKS remained stopped.
Argo CD was not installed.
