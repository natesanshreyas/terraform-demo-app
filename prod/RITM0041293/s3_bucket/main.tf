module "s3_bucket" {
  source      = "git::https://github.com/natesanshreyas/terraform-modules.git//modules/s3?ref=68380c5"
  name        = "payments-api-s3_bucket-prod"
  environment = "prod"
}
