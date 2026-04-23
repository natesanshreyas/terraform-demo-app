module "app_rg" {
  source      = "git::https://github.com/natesanshreyas/terraform-modules.git//modules/resource_group?ref=68380c5"
  name        = "payments-api-app_rg-prod"
  environment = "prod"
}
