module "storage_account" {
  source      = "git::https://github.com/natesanshreyas/terraform-modules.git//modules/storage?ref=68380c5"
  name        = "payments-api-storage_account-prod"
  environment = "prod"
}
