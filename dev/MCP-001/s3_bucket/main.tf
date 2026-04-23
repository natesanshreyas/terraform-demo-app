module "s3_bucket" {
  source      = "git::https://github.com/natesanshreyas/terraform-modules.git//modules/s3?ref=68380c5"
  name        = "test-app-s3_bucket-dev"
  environment = "dev"
}
