module "postgres_flex" {
  source = "git::https://github.com/acme/terraform-azure-modules.git//modules/postgres_flex?ref=68380c5"

  location              = "eastus2"
  resource_group_name   = "rg-payments-api-prod"
  name                  = "payments-api-postgres_flex-prod"
  environment           = "prod"
  sku_name              = GP_Standard_D2s_v3
  storage_mb            = 65536
  backup_retention_days = 7
  administrator_login   = psqladmin
  administrator_password= var.postgres_admin_password  # injected via CI secret
  high_availability     = false
  version               = "16"

  tags = {
    ticket_id   = "RITM0041293"
    environment = "prod"
    managed_by  = "snow-tf-platform"
  }
}
