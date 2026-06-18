terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }

  # Default: local backend (terraform.tfstate in working directory)
  # For team use, configure a remote backend:
  # backend "azurerm" {
  #   resource_group_name  = "rg-terraform-state"
  #   storage_account_name = "yourstateaccount"
  #   container_name       = "tfstate"
  #   key                  = "ssl-cert-monitor.tfstate"
  # }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

resource "azurerm_resource_group" "this" {
  name     = var.resource_group_name
  location = var.location
}

# Azure Communication Services
resource "azurerm_communication_service" "this" {
  name                = var.communication_service_name
  resource_group_name = azurerm_resource_group.this.name
  data_location       = var.data_location
}

# Email Communication Services
resource "azurerm_email_communication_service" "this" {
  name                = var.email_service_name
  resource_group_name = azurerm_resource_group.this.name
  data_location       = var.data_location
}

# Azure Managed Domain (free, no custom DNS needed)
resource "azurerm_email_communication_service_domain" "managed" {
  name             = "AzureManagedDomain"
  email_service_id = azurerm_email_communication_service.this.id
  domain_management = "AzureManaged"
}

# Connect email domain to communication service
resource "azurerm_communication_service_email_domain_association" "this" {
  communication_service_id = azurerm_communication_service.this.id
  email_service_domain_id  = azurerm_email_communication_service_domain.managed.id
}
