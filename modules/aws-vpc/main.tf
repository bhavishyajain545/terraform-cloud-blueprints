data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

locals {
  tags = merge(var.tags, { "managed-by" = "terraform", "module" = "aws-vpc" })

  az_count = length(var.azs)

  # Default layout for a /16: publics are /24s at the bottom (10.x.0-5.0), privates are /20s from 10.x.16.0 up.
  public_cidrs  = length(var.public_subnet_cidrs) > 0 ? var.public_subnet_cidrs : [for i in range(local.az_count) : cidrsubnet(var.cidr_block, 8, i)]
  private_cidrs = length(var.private_subnet_cidrs) > 0 ? var.private_subnet_cidrs : [for i in range(local.az_count) : cidrsubnet(var.cidr_block, 4, i + 1)]

  nat_count = {
    per_az = local.az_count
    single = 1
    none   = 0
  }[var.nat_gateway_mode]

  # Which NAT gateway each private route table uses.
  nat_index_for_az = [for i in range(local.az_count) : var.nat_gateway_mode == "per_az" ? i : 0]
}

###############################################################################
# VPC
###############################################################################

resource "aws_vpc" "this" {
  cidr_block           = var.cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = merge(local.tags, { Name = "vpc-${var.name}" })
}

# Take ownership of the default SG and strip all rules, so nothing that lands on it
# by accident (e.g. an ENI without explicit SGs) can talk to anything.
resource "aws_default_security_group" "this" {
  vpc_id = aws_vpc.this.id
  tags   = merge(local.tags, { Name = "sg-${var.name}-default-deny" })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = merge(local.tags, { Name = "igw-${var.name}" })
}

###############################################################################
# Subnets
###############################################################################

resource "aws_subnet" "public" {
  count = local.az_count

  vpc_id                  = aws_vpc.this.id
  availability_zone       = var.azs[count.index]
  cidr_block              = local.public_cidrs[count.index]
  map_public_ip_on_launch = false

  tags = merge(local.tags, var.public_subnet_tags, {
    Name                     = "snet-${var.name}-public-${var.azs[count.index]}"
    Tier                     = "public"
    "kubernetes.io/role/elb" = "1"
  })
}

resource "aws_subnet" "private" {
  count = local.az_count

  vpc_id            = aws_vpc.this.id
  availability_zone = var.azs[count.index]
  cidr_block        = local.private_cidrs[count.index]

  tags = merge(local.tags, var.private_subnet_tags, {
    Name                              = "snet-${var.name}-private-${var.azs[count.index]}"
    Tier                              = "private"
    "kubernetes.io/role/internal-elb" = "1"
  })
}

###############################################################################
# NAT
###############################################################################

resource "aws_eip" "nat" {
  count = local.nat_count

  domain = "vpc"
  tags   = merge(local.tags, { Name = "eip-${var.name}-nat-${var.azs[count.index]}" })

  depends_on = [aws_internet_gateway.this]
}

resource "aws_nat_gateway" "this" {
  count = local.nat_count

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id
  tags          = merge(local.tags, { Name = "nat-${var.name}-${var.azs[count.index]}" })

  depends_on = [aws_internet_gateway.this]
}

###############################################################################
# Routing
###############################################################################

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  tags   = merge(local.tags, { Name = "rt-${var.name}-public" })
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  count = local.az_count

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# One private route table per AZ even with a single NAT: switching nat_gateway_mode
# later only changes routes, never subnet associations.
resource "aws_route_table" "private" {
  count = local.az_count

  vpc_id = aws_vpc.this.id
  tags   = merge(local.tags, { Name = "rt-${var.name}-private-${var.azs[count.index]}" })
}

resource "aws_route" "private_nat" {
  count = var.nat_gateway_mode == "none" ? 0 : local.az_count

  route_table_id         = aws_route_table.private[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[local.nat_index_for_az[count.index]].id
}

resource "aws_route_table_association" "private" {
  count = local.az_count

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

resource "aws_vpc_endpoint" "s3" {
  count = var.enable_s3_gateway_endpoint ? 1 : 0

  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${data.aws_region.current.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = aws_route_table.private[*].id
  tags              = merge(local.tags, { Name = "vpce-${var.name}-s3" })
}

###############################################################################
# Flow logs -> CloudWatch Logs (KMS encrypted)
###############################################################################

resource "aws_kms_key" "flow_logs" {
  count = var.flow_logs.enabled ? 1 : 0

  description             = "CMK for VPC flow logs of ${var.name}"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  tags                    = local.tags

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AccountAdmin"
        Effect    = "Allow"
        Principal = { AWS = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid       = "CloudWatchLogs"
        Effect    = "Allow"
        Principal = { Service = "logs.${data.aws_region.current.region}.amazonaws.com" }
        Action    = ["kms:Encrypt*", "kms:Decrypt*", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:Describe*"]
        Resource  = "*"
        Condition = {
          ArnLike = {
            "kms:EncryptionContext:aws:logs:arn" = "arn:${data.aws_partition.current.partition}:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/vpc/${var.name}/flow-logs"
          }
        }
      },
    ]
  })
}

resource "aws_kms_alias" "flow_logs" {
  count = var.flow_logs.enabled ? 1 : 0

  name          = "alias/${var.name}-flow-logs"
  target_key_id = aws_kms_key.flow_logs[0].key_id
}

resource "aws_cloudwatch_log_group" "flow_logs" {
  count = var.flow_logs.enabled ? 1 : 0

  name              = "/aws/vpc/${var.name}/flow-logs"
  retention_in_days = var.flow_logs.retention_days
  kms_key_id        = aws_kms_key.flow_logs[0].arn
  tags              = local.tags
}

resource "aws_iam_role" "flow_logs" {
  count = var.flow_logs.enabled ? 1 : 0

  name = "${var.name}-vpc-flow-logs"
  tags = local.tags

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "vpc-flow-logs.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = {
        StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
      }
    }]
  })
}

resource "aws_iam_role_policy" "flow_logs" {
  count = var.flow_logs.enabled ? 1 : 0

  name = "write-flow-logs"
  role = aws_iam_role.flow_logs[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams"]
      Resource = "${aws_cloudwatch_log_group.flow_logs[0].arn}:*"
    }]
  })
}

resource "aws_flow_log" "this" {
  count = var.flow_logs.enabled ? 1 : 0

  vpc_id                   = aws_vpc.this.id
  traffic_type             = var.flow_logs.traffic_type
  log_destination_type     = "cloud-watch-logs"
  log_destination          = aws_cloudwatch_log_group.flow_logs[0].arn
  iam_role_arn             = aws_iam_role.flow_logs[0].arn
  max_aggregation_interval = var.flow_logs.max_aggregation_interval
  tags                     = merge(local.tags, { Name = "fl-${var.name}" })
}
