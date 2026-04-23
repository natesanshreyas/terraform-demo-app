module "postgres_flex" {
  source      = "git::https://github.com/natesanshreyas/terraform-modules.git//modules/postgres_flex?ref=68380c5"
  name        = "payments-api-postgres_flex-prod"
  environment = "prod"
}
