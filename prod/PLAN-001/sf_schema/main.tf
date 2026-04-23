module "sf_schema" {
  source      = "git::https://github.com/natesanshreyas/terraform-modules.git//modules/schema?ref=68380c5"
  name        = "test-sf_schema-prod"
  environment = "prod"
}
