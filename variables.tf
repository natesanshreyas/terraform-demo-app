variable "project_name" {
  description = "Short project name used in resource naming."
  type        = string
  default     = "tdemo"
}

variable "environment" {
  description = "Environment name used in resource naming."
  type        = string
  default     = "dev"
}

variable "location" {
  description = "Azure region for all resources."
  type        = string
  default     = "eastus2"
}

variable "webhook_base_url" {
  description = "Public HTTPS base URL for the Function webhook endpoint (for Graph notifications)."
  type        = string
}

variable "graph_subscription_client_state" {
  description = "Shared secret used by Graph notifications for request validation."
  type        = string
  sensitive   = true
}

variable "azure_openai_deployment_name" {
  description = "Azure OpenAI chat deployment name used for transcript analysis."
  type        = string
  default     = "gpt-4o"
}

variable "create_openai_resource" {
  description = "When true, provision a new Azure OpenAI account; otherwise provide endpoint and key via variables."
  type        = bool
  default     = false
}

variable "azure_openai_existing_endpoint" {
  description = "Existing Azure OpenAI endpoint URL when create_openai_resource is false."
  type        = string
  default     = ""
}

variable "azure_openai_api_key" {
  description = "Azure OpenAI API key when create_openai_resource is false."
  type        = string
  sensitive   = true
  default     = ""
}

variable "analysis_blob_name" {
  description = "Append blob name used to store transcript analysis output."
  type        = string
  default     = "teams-transcript-analysis.md"
}
