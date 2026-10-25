# Composition test: the whole aws-dev stack plans and "applies" against a mocked provider.

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "111122223333"
    }
  }
  mock_data "aws_region" {
    defaults = {
      region = "eu-west-1"
    }
  }
  mock_data "aws_partition" {
    defaults = {
      partition = "aws"
    }
  }
  mock_resource "aws_kms_key" {
    defaults = {
      arn = "arn:aws:kms:eu-west-1:111122223333:key/00000000-0000-0000-0000-000000000000"
    }
  }
  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::111122223333:role/mocked"
    }
  }
  mock_resource "aws_cloudwatch_log_group" {
    defaults = {
      arn = "arn:aws:logs:eu-west-1:111122223333:log-group:mocked"
    }
  }
  mock_resource "aws_iam_openid_connect_provider" {
    defaults = {
      arn = "arn:aws:iam::111122223333:oidc-provider/oidc.eks.eu-west-1.amazonaws.com/id/EXAMPLE"
    }
  }
  mock_resource "aws_eks_cluster" {
    defaults = {
      arn                   = "arn:aws:eks:eu-west-1:111122223333:cluster/blueprint-dev"
      certificate_authority = [{ data = "bW9jay1jYQ==" }]
      identity = [{
        oidc = [{ issuer = "https://oidc.eks.eu-west-1.amazonaws.com/id/EXAMPLE" }]
      }]
    }
  }
  mock_resource "aws_launch_template" {
    defaults = {
      id             = "lt-0123456789abcdef0"
      latest_version = 1
    }
  }
}

run "private_by_default" {
  command = plan

  assert {
    condition     = module.eks.cluster_name == "blueprint-dev"
    error_message = "Unexpected cluster name."
  }
}

run "stack_applies_with_mocks" {
  command = apply

  variables {
    endpoint_public_access       = true
    endpoint_public_access_cidrs = ["198.51.100.10/32"]
    cluster_admin_role_arn       = "arn:aws:iam::111122223333:role/platform-admins"
  }

  assert {
    condition     = length(module.vpc.private_subnet_ids) == 3 && length(module.vpc.nat_gateway_ids) == 1
    error_message = "Dev VPC must span 3 AZs with a single NAT gateway."
  }

  assert {
    condition     = module.eks.oidc_provider_arn != ""
    error_message = "IRSA OIDC provider must be created."
  }
}
