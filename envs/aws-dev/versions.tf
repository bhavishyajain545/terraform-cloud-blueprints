terraform {
  required_version = ">= 1.9.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.70"
    }
  }
}

provider "aws" {
  # Credentials come from the environment (SSO profile locally, OIDC role in CI). Nothing secret here.
  region = var.region

  # Guard rail: refuse to run against any account other than the intended one.
  allowed_account_ids = var.allowed_account_ids

  default_tags {
    tags = {
      environment = "dev"
      project     = "terraform-cloud-blueprints"
      cost-center = "platform"
      managed-by  = "terraform"
    }
  }
}
