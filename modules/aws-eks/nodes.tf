###############################################################################
# Node IAM role
# The CNI policy lives on the vpc-cni IRSA role, not on the node, so pods that
# can reach instance credentials cannot manipulate ENIs. If vpc-cni is not a
# managed add-on here, the policy falls back to the node role.
###############################################################################

locals {
  node_policy_arns = merge(
    {
      worker = "arn:${local.partition}:iam::aws:policy/AmazonEKSWorkerNodePolicy"
      ecr    = "arn:${local.partition}:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly"
    },
    var.node_ssm_access ? { ssm = "arn:${local.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore" } : {},
    contains(keys(var.addons), "vpc-cni") ? {} : { cni = "arn:${local.partition}:iam::aws:policy/AmazonEKS_CNI_Policy" },
  )
}

resource "aws_iam_role" "node" {
  name = "${var.name}-eks-node"
  tags = local.tags

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "node" {
  for_each = local.node_policy_arns

  role       = aws_iam_role.node.name
  policy_arn = each.value
}

###############################################################################
# Launch templates (one per node group)
###############################################################################

resource "aws_launch_template" "node" {
  for_each = var.node_groups

  name_prefix            = "${var.name}-${each.key}-"
  description            = "EKS ${var.name} node group ${each.key}"
  update_default_version = true
  tags                   = local.tags

  # IMDSv2 only, hop limit 1: pods cannot reach the node's instance profile credentials.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "disabled"
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = each.value.disk_size_gb
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  monitoring {
    enabled = true
  }

  tag_specifications {
    resource_type = "instance"
    tags          = merge(local.tags, { Name = "${var.name}-${each.key}" })
  }

  tag_specifications {
    resource_type = "volume"
    tags          = merge(local.tags, { Name = "${var.name}-${each.key}" })
  }

  lifecycle {
    create_before_destroy = true
  }
}

###############################################################################
# Managed node groups
###############################################################################

resource "aws_eks_node_group" "this" {
  for_each = var.node_groups

  cluster_name    = aws_eks_cluster.this.name
  node_group_name = each.key
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = coalesce(each.value.subnet_ids, var.subnet_ids)
  instance_types  = each.value.instance_types
  capacity_type   = each.value.capacity_type
  ami_type        = each.value.ami_type
  labels          = each.value.labels
  tags            = local.tags

  scaling_config {
    min_size     = each.value.min_size
    max_size     = each.value.max_size
    desired_size = coalesce(each.value.desired_size, each.value.min_size == 0 ? 1 : each.value.min_size)
  }

  update_config {
    max_unavailable_percentage = each.value.max_unavailable_percentage
  }

  launch_template {
    id      = aws_launch_template.node[each.key].id
    version = aws_launch_template.node[each.key].latest_version
  }

  node_repair_config {
    enabled = true
  }

  dynamic "taint" {
    for_each = each.value.taints
    content {
      key    = taint.value.key
      value  = taint.value.value
      effect = taint.value.effect
    }
  }

  lifecycle {
    # Cluster Autoscaler / Karpenter own the current size.
    ignore_changes = [scaling_config[0].desired_size]
  }

  depends_on = [
    aws_iam_role_policy_attachment.node,
    aws_eks_addon.before_compute,
  ]
}
