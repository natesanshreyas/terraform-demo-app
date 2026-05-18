output "resource_group_name" {
  value = azurerm_resource_group.main.name
}

output "function_app_name" {
  value = azurerm_linux_function_app.main.name
}

output "function_webhook_url" {
  value = "${trim(var.webhook_base_url, "/")}/api/graph/notifications"
}

output "graph_application_client_id" {
  value = azuread_application.transcript_ingestor.client_id
}

output "key_vault_name" {
  value = azurerm_key_vault.main.name
}

output "analysis_blob_container" {
  value = azurerm_storage_container.analysis.name
}

output "analysis_blob_name" {
  value = var.analysis_blob_name
}

output "storage_queue_name" {
  value = azurerm_storage_queue.transcripts.name
}
