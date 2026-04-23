module "rds_postgres" {
  source      = "git::https://github.com/natesanshreyas/terraform-modules.git//modules/rds_postgres?ref=68380c5"
  name        = "payments-api-rds_postgres-prod"
  environment = "prod"
}
