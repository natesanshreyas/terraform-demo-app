module "vpc" {
  source      = "git::https://github.com/natesanshreyas/terraform-modules.git//modules/vpc?ref=68380c5"
  name        = "test-app-vpc-dev"
  environment = "dev"
}
