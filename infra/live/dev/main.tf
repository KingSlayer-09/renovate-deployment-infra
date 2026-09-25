terraform {
  required_version = ">= 1.10.0"
  backend "s3" {
    key          = "dev/terraform.tfstate"
    use_lockfile = true
    encrypt      = true
  }
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Project     = var.project_name
      Environment = "dev"
      ManagedBy   = "Terraform"
    }
  }
}

module "app_stack" {
  source             = "../../modules/app_stack"
  project_name       = var.project_name
  environment        = "dev"
  vpc_cidr           = var.vpc_cidr
  image_tag          = var.image_tag
  ecs_desired_count  = var.ecs_desired_count
  log_retention_days = var.log_retention_days
}

output "api_url" { value = module.app_stack.api_url }
output "ecs_url" { value = module.app_stack.ecs_url }
output "data_bucket" { value = module.app_stack.data_bucket }
output "secret_arn" { value = module.app_stack.secret_arn }
output "ecs_cluster" { value = module.app_stack.ecs_cluster }
output "ecs_service" { value = module.app_stack.ecs_service }
