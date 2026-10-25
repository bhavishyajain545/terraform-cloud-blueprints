output "vpc_id" {
  description = "VPC ID."
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnets used by EKS."
  value       = module.vpc.private_subnet_ids
}

output "nat_public_ips" {
  description = "Egress IPs to allow-list at third parties."
  value       = module.vpc.nat_public_ips
}

output "cluster_name" {
  description = "EKS cluster name (aws eks update-kubeconfig --name ...)."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS API endpoint."
  value       = module.eks.cluster_endpoint
}

output "oidc_provider_arn" {
  description = "OIDC provider ARN for IRSA roles."
  value       = module.eks.oidc_provider_arn
}
