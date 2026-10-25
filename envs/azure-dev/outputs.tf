output "resource_group_name" {
  description = "Resource group holding the environment."
  value       = azurerm_resource_group.this.name
}

output "cluster_name" {
  description = "AKS cluster name (az aks get-credentials --name ...)."
  value       = module.aks.cluster_name
}

output "api_server_fqdn" {
  description = "Private API server FQDN."
  value       = module.aks.api_server_fqdn
}

output "oidc_issuer_url" {
  description = "Issuer for Workload ID federated credentials."
  value       = module.aks.oidc_issuer_url
}

output "acr_login_server" {
  description = "Registry login server."
  value       = module.aks.acr_login_server
}

output "key_vault_uri" {
  description = "Key Vault URI."
  value       = module.aks.key_vault_uri
}

output "subnet_ids" {
  description = "Subnets created for the environment."
  value       = module.network.subnet_ids
}
