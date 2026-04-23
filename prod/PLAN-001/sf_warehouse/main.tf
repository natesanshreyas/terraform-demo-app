module "sf_warehouse" {
  source      = "git::https://github.com/natesanshreyas/terraform-modules.git//modules/warehouse?ref=68380c5"
  name        = "test-sf_warehouse-prod"
  environment = "prod"
}
