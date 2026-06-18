variable "subscription_id" {
  description = "Azure subscription ID"
  type        = string
}

variable "resource_group_name" {
  description = "Resource group name"
  type        = string
  default     = "rg-ssl-monitor"
}

variable "location" {
  description = "Azure region for the resource group"
  type        = string
  default     = "australiaeast"
}

variable "data_location" {
  description = "Data location for communication services (e.g. Australia, United States, Europe, UK, Japan, Korea, Africa, Brazil)"
  type        = string
  default     = "Australia"
}

variable "communication_service_name" {
  description = "Name of the Communication Service resource"
  type        = string
  default     = "acs-ssl-monitor"
}

variable "email_service_name" {
  description = "Name of the Email Communication Service resource"
  type        = string
  default     = "email-ssl-monitor"
}
