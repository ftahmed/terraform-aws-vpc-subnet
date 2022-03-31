provider "aws" {
  region = var.region
  profile = var.profile
}

module "networking" {
  source = "./modules/networking"

  project              = var.project
  environment          = var.environment
  region               = var.region
  availability_zones   = var.availability_zones
  vpc_cidr             = var.vpc_cidr
  public_subnets_cidr  = var.public_subnets_cidr
  private_subnets_cidr = var.private_subnets_cidr
}

/*
module "ec2" {
  source = "./modules/ec2"

  project              = var.project
  environment          = var.environment
  region               = var.region
  availability_zones   = var.availability_zones
  vpc_id               = module.networking.vpc.id
  vpc_cidr             = var.vpc_cidr
  public_subnets_cidr  = var.public_subnets_cidr
  private_subnets_cidr = var.private_subnets_cidr
}
*/
