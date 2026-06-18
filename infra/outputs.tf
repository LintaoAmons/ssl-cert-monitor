output "connection_string" {
  description = "ACS connection string for send-email-acs.sh"
  value       = azurerm_communication_service.this.primary_connection_string
  sensitive   = true
}

output "sender_address" {
  description = "Default sender address (DoNotReply@<domain>.azurecomm.net)"
  value       = "DoNotReply@${azurerm_email_communication_service_domain.managed.from_sender_domain}"
}

output "resource_group" {
  description = "Resource group name"
  value       = azurerm_resource_group.this.name
}
