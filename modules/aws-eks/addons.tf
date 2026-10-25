###############################################################################
# IRSA roles for add-ons that call AWS APIs
###############################################################################

locals {
  oidc_issuer_host = replace(aws_eks_cluster.this.identity[0].oidc[0].issuer, "https://", "")

  irsa_catalog = {
    "vpc-cni" = {
      namespace       = "kube-system"
      service_account = "aws-node"
      policy_arn      = "arn:${local.partition}:iam::aws:policy/AmazonEKS_CNI_Policy"
    }
    "aws-ebs-csi-driver" = {
      namespace       = "kube-system"
      service_account = "ebs-csi-controller-sa"
      policy_arn      = "arn:${local.partition}:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
    }
  }

  irsa_roles = { for k, v in local.irsa_catalog : k => v if contains(keys(var.addons), k) }
}

resource "aws_iam_role" "irsa" {
  for_each = local.irsa_roles

  name = "${var.name}-irsa-${each.key}"
  tags = local.tags

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.this.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_issuer_host}:sub" = "system:serviceaccount:${each.value.namespace}:${each.value.service_account}"
          "${local.oidc_issuer_host}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "irsa" {
  for_each = local.irsa_roles

  role       = aws_iam_role.irsa[each.key].name
  policy_arn = each.value.policy_arn
}

###############################################################################
# Managed add-ons
###############################################################################

resource "aws_eks_addon" "before_compute" {
  for_each = { for k, v in var.addons : k => v if v.before_compute }

  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = each.key
  addon_version               = each.value.version
  configuration_values        = each.value.configuration_values
  service_account_role_arn    = contains(keys(local.irsa_roles), each.key) ? aws_iam_role.irsa[each.key].arn : null
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  tags                        = local.tags

  depends_on = [aws_iam_role_policy_attachment.irsa]
}

resource "aws_eks_addon" "this" {
  for_each = { for k, v in var.addons : k => v if !v.before_compute }

  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = each.key
  addon_version               = each.value.version
  configuration_values        = each.value.configuration_values
  service_account_role_arn    = contains(keys(local.irsa_roles), each.key) ? aws_iam_role.irsa[each.key].arn : null
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  tags                        = local.tags

  # coredns / ebs-csi need schedulable nodes to become ACTIVE.
  depends_on = [
    aws_eks_node_group.this,
    aws_iam_role_policy_attachment.irsa,
  ]
}
