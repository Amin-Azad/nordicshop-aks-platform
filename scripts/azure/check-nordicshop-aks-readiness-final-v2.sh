#!/usr/bin/env bash
set -uo pipefail

# NordicShop AKS Platform - minimal read-only readiness check
# Run from repository root:
#   bash scripts/azure/check-nordicshop-aks-readiness.sh

REGION="${REGION:-westeurope}"
RESOURCE_GROUP="${RESOURCE_GROUP:-rg-nordicshop-dev-weu}"
VNET_NAME="${VNET_NAME:-vnet-nordicshop-dev}"

EVIDENCE_DIR="docs/evidence"
mkdir -p "$EVIDENCE_DIR"
OUT="${EVIDENCE_DIR}/aks-readiness-$(date +%Y%m%d-%H%M).txt"

section() {
  echo
  echo "=================================================="
  echo "$1"
  echo "=================================================="
}

{
  section "NORDICSHOP AKS READINESS - ${REGION}"

  echo "[1/5] Azure context"
  az account show \
    --query "{subscription:name,state:state,tenant:tenantId}" \
    -o table

  section "[2/5] Required providers"
  for provider in \
    Microsoft.ContainerService \
    Microsoft.Compute \
    Microsoft.Network \
    Microsoft.ContainerRegistry \
    Microsoft.ManagedIdentity \
    Microsoft.OperationalInsights \
    Microsoft.Insights \
    Microsoft.KeyVault
  do
    state="$(az provider show --namespace "$provider" --query registrationState -o tsv 2>/dev/null || echo UNKNOWN)"
    printf "%-38s %s\n" "$provider" "$state"
  done

  section "[3/5] Existing NordicShop network"

  az network vnet show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$VNET_NAME" \
    --query "{vnet:name,addressSpace:addressSpace.addressPrefixes}" \
    -o json

  az network vnet subnet list \
    --resource-group "$RESOURCE_GROUP" \
    --vnet-name "$VNET_NAME" \
    --query "[].{name:name,addressPrefixes:addressPrefixes}" \
    -o json

  section "[4/5] AKS versions + compute quota"

  echo "AKS versions currently offered in ${REGION}:"
  az aks get-versions \
    --location "$REGION" \
    --output table | grep -E '^1\.36|^1\.35|^KubernetesVersion|^---' || true

  echo
  echo "Relevant compute quota:"
  az vm list-usage \
    --location "$REGION" \
    --query "[].{Quota:name.localizedValue,Used:currentValue,Limit:limit}" \
    -o table | grep -E 'Quota|---|Total Regional vCPUs|D.*Family vCPUs|F.*Family vCPUs' || true

  section "[5/5] Small 4-vCPU AKS node candidates"

  echo "Candidate D/F-family SKUs in ${REGION}:"
  az vm list-skus \
    --location "$REGION" \
    --resource-type virtualMachines \
    --all false \
    --query "[].{Name:name,vCPU:capabilities[?name=='vCPUs'].value | [0],RAM:capabilities[?name=='MemoryGB'].value | [0]}" \
    -o table | grep -E '^Standard_(D4|F4)|^Name|^---' | head -25 || true

  section "CURRENT NORDICSHOP AKS DESIGN"

  echo "Region:              ${REGION}"
  echo "VNet:                10.20.0.0/16"
  echo "AKS subnet:          10.20.0.0/22"
  echo "Reserved PE subnet:  10.20.4.0/24"
  echo "Pod CIDR:            10.244.0.0/16"
  echo "Service CIDR:        10.30.0.0/16"
  echo "DNS service IP:      10.30.0.10"
  echo "Kubernetes target:   1.36"
  echo "Node target:         small non-B-series 4-vCPU system node SKU"
  echo
  echo "This script makes no Azure changes."
  echo "Review this report before Terraform plan/apply."

} 2>&1 | tee "$OUT"

echo
echo "Saved evidence to: $OUT"
