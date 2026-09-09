terraform {
  backend "azurerm" {
    resource_group_name  = "rg-tfstate-nordicshop-weu"
    storage_account_name = "stnstf242817791"
    container_name       = "tfstate"
    key                  = "dev.terraform.tfstate"
  }
}