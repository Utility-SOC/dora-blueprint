terraform {
  required_version = ">= 1.10"

  # Partial config -- bucket/region come from infra/aws/persistent's outputs via
  # `make cloud-up`, which writes backend.hcl. State locks natively in S3 (use_lockfile).
  backend "s3" {}

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
      stack      = "cluster"
      lab        = var.name
      expires-at = var.expires_at
      managed-by = "opentofu"
    }
  }
}
