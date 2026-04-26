module "storage_account" {
  source = "git::https://github.com/acme/terraform-azure-modules.git//modules/storage?ref=68380c5"

  location              = "eastus2"
  resource_group_name   = "rg-payments-api-prod"
  name                  = "payments-api-storage_account-prod"
  environment           = "prod"
  account_tier          = Standard
  account_replication_type= LRS
  enable_https_traffic_only= true
  min_tls_version       = TLS1_2

  tags = {
    ticket_id   = "RITM0041293"
    environment = "prod"
    managed_by  = "snow-tf-platform"
  }
}
