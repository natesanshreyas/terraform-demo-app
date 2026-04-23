module "storage_account" {
  source      = "git::https://github.com/natesanshreyas/terraform-modules.git//modules/storage?ref=68380c5"
  name        = "smoke-test-storage_account-dev"
  environment = "dev"
}
