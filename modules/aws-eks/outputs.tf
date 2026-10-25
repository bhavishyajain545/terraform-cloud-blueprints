output "cluster_name" {
  description = "Name of the EKS cluster."
  value       = aws_eks_cluster.this.name
}

output "cluster_arn" {
  description = "ARN of the EKS cluster."
  value       = aws_eks_cluster.this.arn
}

output "cluster_endpoint" {
  description = "API server endpoint."
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64 CA bundle of the API server (for kubeconfig / the kubernetes provider)."
  value       = aws_eks_cluster.this.certificate_authority[0].data
}

output "cluster_security_group_id" {
  description = "EKS-managed cluster security group (attached to control plane ENIs and managed nodes)."
  value       = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

output "oidc_issuer_url" {
  description = "OIDC issuer URL of the cluster."
  value       = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

output "oidc_provider_arn" {
  description = "IAM OIDC provider ARN - use as the Federated principal in IRSA trust policies."
  value       = aws_iam_openid_connect_provider.this.arn
}

output "node_role_arn" {
  description = "IAM role ARN used by managed node groups."
  value       = aws_iam_role.node.arn
}

output "node_group_arns" {
  description = "Map of node group name => ARN."
  value       = { for k, g in aws_eks_node_group.this : k => g.arn }
}

output "kms_key_arn" {
  description = "KMS key used for Secrets envelope encryption and control plane logs."
  value       = local.kms_key_arn
}

output "irsa_role_arns" {
  description = "Map of add-on name => IRSA role ARN created by this module."
  value       = { for k, r in aws_iam_role.irsa : k => r.arn }
}

output "log_group_name" {
  description = "CloudWatch log group for control plane logs."
  value       = aws_cloudwatch_log_group.this.name
}
