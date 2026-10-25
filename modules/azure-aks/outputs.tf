output "cluster_id" {
  description = "Resource ID of the AKS cluster."
  value       = azurerm_kubernetes_cluster.this.id
}

output "cluster_name" {
  description = "Name of the AKS cluster."
  value       = azurerm_kubernetes_cluster.this.name
}

output "node_resource_group" {
  description = "Resource group AKS uses for node VMSS, load balancers and disks."
  value       = azurerm_kubernetes_cluster.this.node_resource_group
}

output "api_server_fqdn" {
  description = "API server FQDN: the private FQDN for private clusters, otherwise the public one."
  value       = var.private_cluster_enabled ? azurerm_kubernetes_cluster.this.private_fqdn : azurerm_kubernetes_cluster.this.fqdn
}

output "oidc_issuer_url" {
  description = "OIDC issuer URL, used as the issuer of federated identity credentials for Workload ID."
  value       = azurerm_kubernetes_cluster.this.oidc_issuer_url
}

output "kubelet_identity" {
  description = "User-assigned identity used by the kubelet (image pulls)."
  value = {
    id           = azurerm_user_assigned_identity.kubelet.id
    client_id    = azurerm_user_assigned_identity.kubelet.client_id
    principal_id = azurerm_user_assigned_identity.kubelet.principal_id
  }
}

output "control_plane_identity_id" {
  description = "Resource ID of the control plane user-assigned identity."
  value       = azurerm_user_assigned_identity.control_plane.id
}

output "user_node_pool_ids" {
  description = "Map of user node pool name => resource ID."
  value       = { for k, p in azurerm_kubernetes_cluster_node_pool.user : k => p.id }
}

output "log_analytics_workspace_id" {
  description = "Log Analytics workspace receiving Container Insights and diagnostic logs."
  value       = local.law_id
}

output "acr_id" {
  description = "Resource ID of the container registry (null if disabled)."
  value       = one(azurerm_container_registry.this[*].id)
}

output "acr_login_server" {
  description = "Login server of the container registry (null if disabled)."
  value       = one(azurerm_container_registry.this[*].login_server)
}

output "key_vault_id" {
  description = "Resource ID of the Key Vault (null if disabled)."
  value       = one(azurerm_key_vault.this[*].id)
}

output "key_vault_uri" {
  description = "Vault URI for SDKs and the Secrets Store CSI SecretProviderClass (null if disabled)."
  value       = one(azurerm_key_vault.this[*].vault_uri)
}

output "secrets_provider_identity_client_id" {
  description = "Client ID of the Secrets Store CSI driver identity, for SecretProviderClass userAssignedIdentityID."
  value       = azurerm_kubernetes_cluster.this.key_vault_secrets_provider[0].secret_identity[0].client_id
}
