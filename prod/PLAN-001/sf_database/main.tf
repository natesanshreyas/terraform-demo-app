module "sf_database" {
  source      = "git::https://github.com/natesanshreyas/terraform-modules.git//modules/database?ref=68380c5"
  name        = "test-sf_database-prod"
  environment = "prod"
}
