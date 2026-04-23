module "app_rg" {
  source      = "git::https://github.com/natesanshreyas/terraform-modules.git//modules/resource_group?ref=68380c5"
  name        = "smoke-test-app_rg-dev"
  environment = "dev"
}
