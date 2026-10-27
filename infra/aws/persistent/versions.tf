terraform {
  # 1.10+: S3 backends lock natively (use_lockfile) -- no DynamoDB table to manage.
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.70.0"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      project    = var.name_prefix
      stack      = "persistent"
      managed-by = "opentofu"
    }
  }
}
