locals {
  # AZs are pinned explicitly instead of read from aws_availability_zones: the data source's
  # result can grow when AWS adds a zone, which would silently re-plan every subnet.
  azs = [for suffix in var.az_suffixes : "${var.region}${suffix}"]
}

module "vpc" {
  source = "../../modules/aws-vpc"

  name       = var.name
  cidr_block = var.vpc_cidr
  azs        = local.azs

  # Dev: one shared NAT gateway. Production should use "per_az".
  nat_gateway_mode = "single"

  flow_logs = {
    retention_days = 365
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/${var.name}" = "shared"
  }
}

module "eks" {
  source = "../../modules/aws-eks"

  name               = var.name
  kubernetes_version = var.kubernetes_version
  subnet_ids         = module.vpc.private_subnet_ids

  endpoint_public_access       = var.endpoint_public_access
  endpoint_public_access_cidrs = var.endpoint_public_access_cidrs

  # Dev clusters are disposable.
  deletion_protection = false

  access_entries = var.cluster_admin_role_arn == null ? {} : {
    cluster-admin = {
      principal_arn = var.cluster_admin_role_arn
      policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
    }
  }

  node_groups = {
    system = {
      instance_types = ["m7i.large"]
      min_size       = 2
      max_size       = 3
      labels         = { "workload" = "system" }
    }
    spot = {
      instance_types = ["m7i.large", "m6i.large", "m7a.large"]
      capacity_type  = "SPOT"
      min_size       = 0
      max_size       = 6
      labels         = { "workload" = "batch" }
      taints         = [{ key = "capacity", value = "spot", effect = "NO_SCHEDULE" }]
    }
  }
}
