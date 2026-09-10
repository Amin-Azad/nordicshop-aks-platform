project_name   = "nordicshop"
environment    = "dev"
location       = "West Europe"
location_short = "weu"

tags = {
  owner   = "platform"
  purpose = "nordicshop-aks-platform"
}

acr_name = "acrnordicshopazaddevweu"
acr_sku  = "Basic"

aks_kubernetes_version  = "1.36"
aks_system_node_vm_size = "Standard_D4s_v4"
aks_system_node_count   = 2

aks_pod_cidr       = "10.244.0.0/16"
aks_service_cidr   = "10.30.0.0/16"
aks_dns_service_ip = "10.30.0.10"