# Unit tests for modules/aws-eks.
# mock_provider: no AWS credentials, no API calls, no cost. ARN-shaped defaults are
# needed because the provider still validates ARN arguments against mocked values.

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
  mock_resource "aws_iam_openid_connect_provider" {
    defaults = {
      arn = "arn:aws:iam::111122223333:oidc-provider/oidc.eks.eu-west-1.amazonaws.com/id/EXAMPLE"
    }
  }
  mock_resource "aws_eks_cluster" {
    defaults = {
      arn                   = "arn:aws:eks:eu-west-1:111122223333:cluster/unit"
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

variables {
  name       = "unit"
  subnet_ids = ["subnet-0aaaaaaaaaaaaaaaa", "subnet-0bbbbbbbbbbbbbbbb", "subnet-0cccccccccccccccc"]
  tags = {
    environment = "test"
  }
  node_groups = {
    system = {
      instance_types = ["m7i.large"]
      min_size       = 2
      max_size       = 4
    }
    spot = {
      instance_types = ["m7i.xlarge", "m6i.xlarge"]
      capacity_type  = "SPOT"
      min_size       = 0
      max_size       = 10
      taints         = [{ key = "spot", value = "true", effect = "NO_SCHEDULE" }]
    }
  }
}

run "secrets_encryption_enabled" {
  command = apply

  assert {
    condition     = contains(aws_eks_cluster.this.encryption_config[0].resources, "secrets")
    error_message = "Kubernetes Secrets must be envelope-encrypted."
  }

  assert {
    condition     = aws_eks_cluster.this.encryption_config[0].provider[0].key_arn == aws_kms_key.this[0].arn
    error_message = "Secrets encryption must use the module-managed CMK."
  }

  assert {
    condition     = aws_kms_key.this[0].enable_key_rotation == true && aws_kms_key.this[0].deletion_window_in_days == 30
    error_message = "CMK must rotate and have a 30-day deletion window."
  }

  assert {
    condition     = jsondecode(aws_iam_role_policy.cluster_kms.policy).Statement[0].Resource == aws_kms_key.this[0].arn
    error_message = "Cluster role KMS permissions must be scoped to the CMK."
  }
}

run "private_endpoint_by_default" {
  command = plan

  assert {
    condition     = aws_eks_cluster.this.vpc_config[0].endpoint_private_access == true && aws_eks_cluster.this.vpc_config[0].endpoint_public_access == false
    error_message = "API endpoint must be private-only by default."
  }

  assert {
    condition     = aws_eks_cluster.this.access_config[0].authentication_mode == "API" && aws_eks_cluster.this.access_config[0].bootstrap_cluster_creator_admin_permissions == false
    error_message = "Access entries (API mode) without implicit creator admin are required."
  }

  assert {
    condition     = aws_eks_cluster.this.deletion_protection == true && aws_eks_cluster.this.upgrade_policy[0].support_type == "STANDARD"
    error_message = "Deletion protection and STANDARD support policy expected by default."
  }
}

run "public_endpoint_requires_cidrs" {
  command = plan

  variables {
    endpoint_public_access = true
  }

  expect_failures = [var.endpoint_public_access_cidrs]
}

run "public_endpoint_with_cidrs" {
  command = plan

  variables {
    endpoint_public_access       = true
    endpoint_public_access_cidrs = ["198.51.100.0/24"]
  }

  assert {
    condition     = aws_eks_cluster.this.vpc_config[0].endpoint_public_access == true && aws_eks_cluster.this.vpc_config[0].public_access_cidrs == toset(["198.51.100.0/24"])
    error_message = "Public endpoint must be restricted to the given CIDRs."
  }
}

run "rejects_world_open_endpoint" {
  command = plan

  variables {
    endpoint_public_access       = true
    endpoint_public_access_cidrs = ["0.0.0.0/0"]
  }

  expect_failures = [var.endpoint_public_access_cidrs]
}

run "control_plane_logging" {
  command = apply

  assert {
    condition     = length(aws_eks_cluster.this.enabled_cluster_log_types) == 5
    error_message = "All five control plane log types must be enabled by default."
  }

  assert {
    condition     = aws_cloudwatch_log_group.this.name == "/aws/eks/unit/cluster" && aws_cloudwatch_log_group.this.retention_in_days == 365 && aws_cloudwatch_log_group.this.kms_key_id == aws_kms_key.this[0].arn
    error_message = "Log group must use the EKS naming convention, 1-year retention and the CMK."
  }
}

run "managed_node_groups" {
  command = plan

  assert {
    condition     = aws_eks_node_group.this["system"].scaling_config[0].min_size == 2 && aws_eks_node_group.this["system"].scaling_config[0].max_size == 4 && aws_eks_node_group.this["system"].scaling_config[0].desired_size == 2
    error_message = "system node group scaling bounds wrong."
  }

  assert {
    condition     = aws_eks_node_group.this["spot"].capacity_type == "SPOT" && aws_eks_node_group.this["spot"].scaling_config[0].desired_size == 1
    error_message = "Spot group must be SPOT and start with one node when min_size = 0."
  }

  assert {
    condition     = one(aws_eks_node_group.this["spot"].taint).effect == "NO_SCHEDULE"
    error_message = "Taints must be passed to the node group."
  }

  assert {
    condition     = alltrue([for g in aws_eks_node_group.this : g.node_repair_config[0].enabled])
    error_message = "Node auto-repair must be on."
  }
}

run "hardened_launch_templates" {
  command = plan

  assert {
    condition     = alltrue([for lt in aws_launch_template.node : lt.metadata_options[0].http_tokens == "required" && lt.metadata_options[0].http_put_response_hop_limit == 1])
    error_message = "Launch templates must enforce IMDSv2 with hop limit 1."
  }

  assert {
    condition     = alltrue([for lt in aws_launch_template.node : lt.block_device_mappings[0].ebs[0].encrypted == "true" && lt.block_device_mappings[0].ebs[0].volume_type == "gp3"])
    error_message = "Node root volumes must be encrypted gp3."
  }
}

run "irsa_oidc_provider_and_roles" {
  command = apply

  assert {
    condition     = aws_iam_openid_connect_provider.this.url == "https://oidc.eks.eu-west-1.amazonaws.com/id/EXAMPLE" && contains(aws_iam_openid_connect_provider.this.client_id_list, "sts.amazonaws.com")
    error_message = "OIDC provider must point at the cluster issuer with the STS audience."
  }

  assert {
    condition     = jsondecode(aws_iam_role.irsa["vpc-cni"].assume_role_policy).Statement[0].Condition.StringEquals["oidc.eks.eu-west-1.amazonaws.com/id/EXAMPLE:sub"] == "system:serviceaccount:kube-system:aws-node"
    error_message = "vpc-cni IRSA trust must be pinned to the aws-node service account."
  }

  assert {
    condition     = jsondecode(aws_iam_role.irsa["aws-ebs-csi-driver"].assume_role_policy).Statement[0].Condition.StringEquals["oidc.eks.eu-west-1.amazonaws.com/id/EXAMPLE:aud"] == "sts.amazonaws.com"
    error_message = "IRSA trust must check the audience."
  }
}

run "core_addons" {
  command = apply

  assert {
    condition     = toset(keys(aws_eks_addon.before_compute)) == toset(["vpc-cni", "eks-pod-identity-agent"])
    error_message = "Networking add-ons must be installed before compute."
  }

  assert {
    condition     = toset(keys(aws_eks_addon.this)) == toset(["kube-proxy", "coredns", "aws-ebs-csi-driver"])
    error_message = "Remaining core add-ons missing."
  }

  assert {
    condition     = aws_eks_addon.before_compute["vpc-cni"].service_account_role_arn == aws_iam_role.irsa["vpc-cni"].arn
    error_message = "vpc-cni must run with its IRSA role."
  }

  assert {
    condition     = !contains(keys(aws_iam_role_policy_attachment.node), "cni")
    error_message = "CNI policy must not be on the node role when vpc-cni uses IRSA."
  }
}

run "cni_policy_falls_back_to_node_role" {
  command = plan

  variables {
    addons = { coredns = {} }
  }

  assert {
    condition     = contains(keys(aws_iam_role_policy_attachment.node), "cni") && length(aws_iam_role.irsa) == 0
    error_message = "Without the vpc-cni add-on the node role needs the CNI policy and no IRSA roles are created."
  }
}

run "bring_your_own_kms_key" {
  command = plan

  variables {
    kms_key_arn = "arn:aws:kms:eu-west-1:111122223333:key/11111111-1111-1111-1111-111111111111"
  }

  assert {
    condition     = length(aws_kms_key.this) == 0 && aws_eks_cluster.this.encryption_config[0].provider[0].key_arn == var.kms_key_arn
    error_message = "A supplied KMS key must be used instead of creating one."
  }
}

run "namespaced_access_entry" {
  command = plan

  variables {
    access_entries = {
      platform-admins = {
        principal_arn = "arn:aws:iam::111122223333:role/platform-admins"
        policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
      }
      team-a = {
        principal_arn = "arn:aws:iam::111122223333:role/team-a"
        policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSEditPolicy"
        namespaces    = ["team-a"]
      }
    }
  }

  assert {
    condition     = aws_eks_access_policy_association.this["platform-admins"].access_scope[0].type == "cluster" && aws_eks_access_policy_association.this["team-a"].access_scope[0].type == "namespace"
    error_message = "Access scope must follow the namespaces input."
  }
}

run "rejects_inverted_node_group_bounds" {
  command = plan

  variables {
    node_groups = {
      bad = {
        instance_types = ["m7i.large"]
        min_size       = 5
        max_size       = 2
      }
    }
  }

  expect_failures = [var.node_groups]
}

run "rejects_single_subnet" {
  command = plan

  variables {
    subnet_ids = ["subnet-0aaaaaaaaaaaaaaaa"]
  }

  expect_failures = [var.subnet_ids]
}

run "tags_applied" {
  command = plan

  assert {
    condition     = aws_eks_cluster.this.tags["environment"] == "test" && aws_eks_cluster.this.tags["managed-by"] == "terraform"
    error_message = "Tags must be applied to the cluster."
  }

  assert {
    condition     = alltrue([for g in aws_eks_node_group.this : g.tags["environment"] == "test"]) && aws_kms_key.this[0].tags["environment"] == "test"
    error_message = "Tags must be applied to node groups and the KMS key."
  }
}
