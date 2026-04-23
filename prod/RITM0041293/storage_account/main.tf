module "storage_account" {
  source                = "git::https://github.com/natesanshreyas/terraform-modules.git//modules/storage?ref=68380c5"
  location              = "eastus2"
  resource_group_name   = "rg-payments-api-prod"
  name                  = "payments-api-storage_account-prod"
  environment           = "prod"
}
