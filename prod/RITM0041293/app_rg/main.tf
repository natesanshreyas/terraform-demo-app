module "app_rg" {
  source                = "git::https://github.com/natesanshreyas/terraform-modules.git//modules/resource_group?ref=68380c5"
  location              = "eastus2"
  resource_group_name   = "rg-payments-api-prod"
  name                  = "payments-api-app_rg-prod"
  environment           = "prod"
}
