# Unit tests for modules/aws-vpc.
# mock_provider: no AWS credentials, no API calls, no cost.

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
  # Realistic ARNs: the provider still validates ARN-typed arguments against mocked values.
  mock_resource "aws_cloudwatch_log_group" {
    defaults = {
      arn = "arn:aws:logs:eu-west-1:111122223333:log-group:/aws/vpc/unit/flow-logs"
    }
  }
  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::111122223333:role/unit-vpc-flow-logs"
    }
  }
  mock_resource "aws_kms_key" {
    defaults = {
      arn = "arn:aws:kms:eu-west-1:111122223333:key/00000000-0000-0000-0000-000000000000"
    }
  }
}

variables {
  name       = "unit"
  cidr_block = "10.20.0.0/16"
  azs        = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]
  tags = {
    environment = "test"
  }
}

run "subnet_layout_across_azs" {
  command = plan

  assert {
    condition     = length(aws_subnet.public) == 3 && length(aws_subnet.private) == 3
    error_message = "Expected one public and one private subnet per AZ."
  }

  assert {
    condition     = aws_subnet.public[*].cidr_block == ["10.20.0.0/24", "10.20.1.0/24", "10.20.2.0/24"]
    error_message = "Unexpected default public CIDRs."
  }

  assert {
    condition     = aws_subnet.private[*].cidr_block == ["10.20.16.0/20", "10.20.32.0/20", "10.20.48.0/20"]
    error_message = "Unexpected default private CIDRs."
  }

  assert {
    condition     = alltrue([for i, s in aws_subnet.private : s.availability_zone == var.azs[i]])
    error_message = "Private subnets must follow the AZ order."
  }

  assert {
    condition     = alltrue([for s in aws_subnet.public : s.map_public_ip_on_launch == false])
    error_message = "Public subnets must not auto-assign public IPs."
  }

  assert {
    condition     = alltrue([for s in aws_subnet.private : s.tags["kubernetes.io/role/internal-elb"] == "1"]) && alltrue([for s in aws_subnet.public : s.tags["kubernetes.io/role/elb"] == "1"])
    error_message = "Subnets must carry the Kubernetes load balancer discovery tags."
  }
}

run "nat_per_az_by_default" {
  command = apply

  assert {
    condition     = length(aws_nat_gateway.this) == 3 && length(aws_eip.nat) == 3
    error_message = "per_az mode must create one NAT gateway + EIP per AZ."
  }

  assert {
    condition     = alltrue([for i in range(3) : aws_route.private_nat[i].nat_gateway_id == aws_nat_gateway.this[i].id])
    error_message = "Each private route table must use the NAT gateway in its own AZ."
  }

  assert {
    condition     = alltrue([for i in range(3) : aws_nat_gateway.this[i].subnet_id == aws_subnet.public[i].id])
    error_message = "NAT gateways must live in the public subnet of their AZ."
  }
}

run "single_nat_toggle" {
  command = apply

  variables {
    nat_gateway_mode = "single"
  }

  assert {
    condition     = length(aws_nat_gateway.this) == 1 && length(aws_eip.nat) == 1
    error_message = "single mode must create exactly one NAT gateway."
  }

  assert {
    condition     = length(aws_route.private_nat) == 3 && alltrue([for r in aws_route.private_nat : r.nat_gateway_id == aws_nat_gateway.this[0].id])
    error_message = "All private route tables must route through the single NAT gateway."
  }
}

run "no_nat_toggle" {
  command = plan

  variables {
    nat_gateway_mode = "none"
  }

  assert {
    condition     = length(aws_nat_gateway.this) == 0 && length(aws_eip.nat) == 0 && length(aws_route.private_nat) == 0
    error_message = "none mode must create no NAT gateways and no default routes in private subnets."
  }

  assert {
    condition     = length(aws_vpc_endpoint.s3) == 1
    error_message = "S3 gateway endpoint should still be created for private-only VPCs."
  }
}

run "flow_logs_enabled_and_encrypted" {
  command = apply

  assert {
    condition     = length(aws_flow_log.this) == 1 && aws_flow_log.this[0].traffic_type == "ALL"
    error_message = "Flow logs must be on by default and capture ALL traffic."
  }

  assert {
    condition     = aws_cloudwatch_log_group.flow_logs[0].retention_in_days == 365 && aws_cloudwatch_log_group.flow_logs[0].kms_key_id == aws_kms_key.flow_logs[0].arn
    error_message = "Flow log group must keep 1 year and be encrypted with the module CMK."
  }

  assert {
    condition     = aws_kms_key.flow_logs[0].enable_key_rotation == true
    error_message = "KMS key rotation must be enabled."
  }

  assert {
    condition     = jsondecode(aws_kms_key.flow_logs[0].policy).Statement[1].Principal.Service == "logs.eu-west-1.amazonaws.com"
    error_message = "KMS key policy must grant the regional CloudWatch Logs service."
  }

  assert {
    condition     = jsondecode(aws_iam_role.flow_logs[0].assume_role_policy).Statement[0].Condition.StringEquals["aws:SourceAccount"] == "111122223333"
    error_message = "Flow log role trust must be scoped to this account (confused-deputy protection)."
  }
}

run "flow_logs_can_be_disabled" {
  command = plan

  variables {
    flow_logs = { enabled = false }
  }

  assert {
    condition     = length(aws_flow_log.this) == 0 && length(aws_kms_key.flow_logs) == 0 && length(aws_cloudwatch_log_group.flow_logs) == 0
    error_message = "Disabling flow logs must remove all related resources."
  }
}

run "default_security_group_locked_down" {
  command = plan

  assert {
    condition     = length(aws_default_security_group.this.ingress) == 0 && length(aws_default_security_group.this.egress) == 0
    error_message = "Default security group must have no rules."
  }
}

run "explicit_cidrs" {
  command = plan

  variables {
    azs                  = ["eu-west-1a", "eu-west-1b"]
    public_subnet_cidrs  = ["10.20.100.0/24", "10.20.101.0/24"]
    private_subnet_cidrs = ["10.20.128.0/18", "10.20.192.0/18"]
  }

  assert {
    condition     = aws_subnet.private[*].cidr_block == ["10.20.128.0/18", "10.20.192.0/18"]
    error_message = "Explicit private CIDRs must be honoured."
  }
}

run "tags_applied" {
  command = plan

  assert {
    condition     = aws_vpc.this.tags["environment"] == "test" && aws_vpc.this.tags["Name"] == "vpc-unit"
    error_message = "Tags and Name must be applied to the VPC."
  }

  assert {
    condition     = alltrue([for s in concat(aws_subnet.public, aws_subnet.private) : s.tags["environment"] == "test" && s.tags["managed-by"] == "terraform"])
    error_message = "Tags must be applied to every subnet."
  }
}

run "rejects_single_az" {
  command = plan

  variables {
    azs = ["eu-west-1a"]
  }

  expect_failures = [var.azs]
}

run "rejects_unknown_nat_mode" {
  command = plan

  variables {
    nat_gateway_mode = "two"
  }

  expect_failures = [var.nat_gateway_mode]
}

run "rejects_cidr_count_mismatch" {
  command = plan

  variables {
    private_subnet_cidrs = ["10.20.128.0/18"]
  }

  expect_failures = [var.private_subnet_cidrs]
}

run "rejects_tiny_vpc" {
  command = plan

  variables {
    cidr_block = "10.20.0.0/26"
  }

  expect_failures = [var.cidr_block]
}
