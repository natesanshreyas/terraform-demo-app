data "azurerm_client_config" "current" {}

data "azuread_application_published_app_ids" "well_known" {}

data "azuread_service_principal" "msgraph" {
  client_id = data.azuread_application_published_app_ids.well_known.result["MicrosoftGraph"]
}

locals {
  required_graph_permissions = toset([
    "Calls.Read.All",
    "OnlineMeetings.Read.All",
    "OnlineMeetingTranscript.Read.All",
  ])

  graph_role_ids = {
    for role in data.azuread_service_principal.msgraph.app_roles :
    role.value => role.id
    if contains(local.required_graph_permissions, role.value) && contains(role.allowed_member_types, "Application")
  }
}

resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

resource "azurerm_resource_group" "main" {
  name     = "rg-${var.project_name}-${var.environment}"
  location = var.location
}

resource "azurerm_storage_account" "main" {
  name                     = "st${replace(var.project_name, "-", "")}${var.environment}${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"
}

resource "azurerm_storage_container" "analysis" {
  name                  = "analysis-docs"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

resource "azurerm_storage_queue" "transcripts" {
  name                 = "transcript-ingestion"
  storage_account_name = azurerm_storage_account.main.name
}

resource "azurerm_servicebus_namespace" "main" {
  name                = "sb-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "Standard"
}

resource "azurerm_servicebus_queue" "transcripts" {
  name         = "transcript-analysis"
  namespace_id = azurerm_servicebus_namespace.main.id
}

resource "azurerm_servicebus_namespace_authorization_rule" "main" {
  name         = "transcript-app"
  namespace_id = azurerm_servicebus_namespace.main.id

  listen = true
  send   = true
  manage = true
}

resource "azurerm_log_analytics_workspace" "main" {
  name                = "law-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
}

resource "azurerm_application_insights" "main" {
  name                = "appi-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = "web"
}

resource "azurerm_service_plan" "main" {
  name                = "asp-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  os_type             = "Linux"
  sku_name            = "Y1"
}

resource "azurerm_cognitive_account" "openai" {
  count = var.create_openai_resource ? 1 : 0

  name                          = "aoai-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  location                      = azurerm_resource_group.main.location
  resource_group_name           = azurerm_resource_group.main.name
  kind                          = "OpenAI"
  sku_name                      = "S0"
  custom_subdomain_name         = "aoai-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  public_network_access_enabled = true
}

resource "azurerm_key_vault" "main" {
  name                          = "kv-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  location                      = azurerm_resource_group.main.location
  resource_group_name           = azurerm_resource_group.main.name
  tenant_id                     = data.azurerm_client_config.current.tenant_id
  sku_name                      = "standard"
  soft_delete_retention_days    = 7
  purge_protection_enabled      = false
  public_network_access_enabled = true
}

resource "azuread_application" "transcript_ingestor" {
  display_name     = "app-${var.project_name}-${var.environment}-transcript-ingestor"
  sign_in_audience = "AzureADMyOrg"

  required_resource_access {
    resource_app_id = data.azuread_application_published_app_ids.well_known.result["MicrosoftGraph"]

    dynamic "resource_access" {
      for_each = local.graph_role_ids
      content {
        id   = resource_access.value
        type = "Role"
      }
    }
  }
}

resource "azuread_service_principal" "transcript_ingestor" {
  client_id = azuread_application.transcript_ingestor.client_id
}

resource "azuread_application_password" "transcript_ingestor" {
  application_id = azuread_application.transcript_ingestor.id
  display_name   = "terraform-managed-client-secret"
}

resource "azuread_app_role_assignment" "graph_permissions" {
  for_each = local.graph_role_ids

  app_role_id         = each.value
  principal_object_id = azuread_service_principal.transcript_ingestor.object_id
  resource_object_id  = data.azuread_service_principal.msgraph.object_id
}

locals {
  openai_endpoint = var.create_openai_resource ? azurerm_cognitive_account.openai[0].endpoint : var.azure_openai_existing_endpoint
  openai_api_key  = var.create_openai_resource ? azurerm_cognitive_account.openai[0].primary_access_key : var.azure_openai_api_key
}

resource "azurerm_key_vault_access_policy" "deployer" {
  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_client_config.current.object_id

  secret_permissions = [
    "Get",
    "Set",
    "Delete",
    "Purge",
    "List",
    "Recover",
  ]
}

resource "azurerm_key_vault_secret" "graph_client_secret" {
  name         = "graph-client-secret"
  value        = azuread_application_password.transcript_ingestor.value
  key_vault_id = azurerm_key_vault.main.id

  depends_on = [azurerm_key_vault_access_policy.deployer]
}

resource "azurerm_key_vault_secret" "openai_api_key" {
  name         = "openai-api-key"
  value        = local.openai_api_key
  key_vault_id = azurerm_key_vault.main.id

  depends_on = [azurerm_key_vault_access_policy.deployer]
}

resource "azurerm_key_vault_secret" "service_bus_connection" {
  name         = "service-bus-connection-string"
  value        = azurerm_servicebus_namespace_authorization_rule.main.primary_connection_string
  key_vault_id = azurerm_key_vault.main.id

  depends_on = [azurerm_key_vault_access_policy.deployer]
}

resource "azurerm_linux_function_app" "main" {
  name                = "func-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  service_plan_id     = azurerm_service_plan.main.id

  storage_account_name       = azurerm_storage_account.main.name
  storage_account_access_key = azurerm_storage_account.main.primary_access_key

  functions_extension_version = "~4"
  https_only                  = true

  identity {
    type = "SystemAssigned"
  }

  site_config {
    application_stack {
      python_version = "3.11"
    }
  }

  app_settings = {
    APPINSIGHTS_INSTRUMENTATIONKEY         = azurerm_application_insights.main.instrumentation_key
    APPLICATIONINSIGHTS_CONNECTION_STRING  = azurerm_application_insights.main.connection_string
    AzureWebJobsStorage                    = azurerm_storage_account.main.primary_connection_string
    FUNCTIONS_WORKER_RUNTIME               = "python"
    WEBSITE_RUN_FROM_PACKAGE               = "1"
    GRAPH_TENANT_ID                        = data.azurerm_client_config.current.tenant_id
    GRAPH_CLIENT_ID                        = azuread_application.transcript_ingestor.client_id
    GRAPH_CLIENT_SECRET                    = "@Microsoft.KeyVault(SecretUri=${azurerm_key_vault_secret.graph_client_secret.id})"
    GRAPH_SUBSCRIPTION_RESOURCE            = "/communications/onlineMeetings/getAllTranscripts"
    GRAPH_SUBSCRIPTION_CLIENT_STATE        = var.graph_subscription_client_state
    GRAPH_NOTIFICATION_URL                 = "${trim(var.webhook_base_url, "/")}/api/graph/notifications"
    TRANSCRIPT_QUEUE_NAME                  = azurerm_storage_queue.transcripts.name
    SERVICE_BUS_QUEUE_NAME                 = azurerm_servicebus_queue.transcripts.name
    SERVICE_BUS_CONNECTION_STRING          = "@Microsoft.KeyVault(SecretUri=${azurerm_key_vault_secret.service_bus_connection.id})"
    ANALYSIS_BLOB_CONTAINER                = azurerm_storage_container.analysis.name
    ANALYSIS_BLOB_NAME                     = var.analysis_blob_name
    AZURE_OPENAI_ENDPOINT                  = local.openai_endpoint
    AZURE_OPENAI_API_KEY                   = "@Microsoft.KeyVault(SecretUri=${azurerm_key_vault_secret.openai_api_key.id})"
    AZURE_OPENAI_DEPLOYMENT                = var.azure_openai_deployment_name
    GRAPH_SUBSCRIPTION_RENEWAL_WINDOW_HOURS = "6"
  }
}

resource "azurerm_key_vault_access_policy" "function_app" {
  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_linux_function_app.main.identity[0].principal_id

  secret_permissions = [
    "Get",
    "List",
  ]
}
