###############################################################################
# Azure Container Registry
###############################################################################

resource "azurerm_container_registry" "this" {
  count = var.acr.enabled ? 1 : 0

  #checkov:skip=CKV_AZURE_166:Quarantine blocks every pull until an external scanner releases the image; enable once such a scanner exists in the pipeline.
  #checkov:skip=CKV_AZURE_165:Geo-replication is a DR decision per environment (cost); not a module default.
  #checkov:skip=CKV_AZURE_164:Content trust (Docker Notary v1) is deprecated by Microsoft; sign images with Notation/cosign instead.
  #checkov:skip=CKV_AZURE_163:Image vulnerability scanning is Defender for Containers, a subscription-level plan (see defender_enabled), not a registry property.
  #checkov:skip=CKV_AZURE_139:Public access is disabled exactly when private endpoints are enabled (dev/prod); checkov cannot evaluate the expression - asserted in tests/azure_aks.tftest.hcl "private_endpoints_disable_public_access".
  name                          = local.acr_name
  location                      = var.location
  resource_group_name           = var.resource_group_name
  sku                           = var.acr.sku
  admin_enabled                 = false
  anonymous_pull_enabled        = false
  public_network_access_enabled = !var.private_endpoints.enabled
  network_rule_bypass_option    = "AzureServices"
  zone_redundancy_enabled       = var.acr.zone_redundancy_enabled
  data_endpoint_enabled         = local.acr_premium
  retention_policy_in_days      = local.acr_premium ? var.acr.retention_days : null
  # Image export can only be blocked when the registry is not publicly reachable.
  export_policy_enabled = !(local.acr_premium && var.private_endpoints.enabled)
  tags                  = local.tags
}

resource "azurerm_role_assignment" "kubelet_acr_pull" {
  count = var.acr.enabled ? 1 : 0

  scope                = azurerm_container_registry.this[0].id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.kubelet.principal_id
  principal_type       = "ServicePrincipal"
  description          = "Nodes pull images from the cluster registry without image pull secrets."
}

resource "azurerm_monitor_diagnostic_setting" "acr" {
  count = var.acr.enabled ? 1 : 0

  name                       = "diag-to-law"
  target_resource_id         = azurerm_container_registry.this[0].id
  log_analytics_workspace_id = local.law_id

  enabled_log {
    category_group = "allLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

###############################################################################
# Key Vault (RBAC authorisation, no access policies)
###############################################################################

# Purge protection + 90-day soft delete already make deletion recoverable; a hard-coded
# prevent_destroy would also block intentional teardown of dev environments and mock tests.
# tflint-ignore: azurerm_resources_missing_prevent_destroy
resource "azurerm_key_vault" "this" {
  count = var.key_vault.enabled ? 1 : 0

  name                          = local.kv_name
  location                      = var.location
  resource_group_name           = var.resource_group_name
  tenant_id                     = data.azurerm_client_config.current.tenant_id
  sku_name                      = var.key_vault.sku_name
  rbac_authorization_enabled    = true
  purge_protection_enabled      = true
  soft_delete_retention_days    = var.key_vault.soft_delete_retention_days
  public_network_access_enabled = !var.private_endpoints.enabled
  tags                          = local.tags

  network_acls {
    default_action = "Deny"
    bypass         = "AzureServices"
    ip_rules       = var.key_vault.allowed_ip_ranges
  }
}

resource "azurerm_role_assignment" "kv_secrets_provider" {
  count = var.key_vault.enabled ? 1 : 0

  scope                = azurerm_key_vault.this[0].id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_kubernetes_cluster.this.key_vault_secrets_provider[0].secret_identity[0].object_id
  principal_type       = "ServicePrincipal"
  description          = "Secrets Store CSI driver reads secrets for workloads."
}

resource "azurerm_role_assignment" "kv_admins" {
  for_each = var.key_vault.enabled ? toset(var.key_vault.admin_principal_ids) : toset([])

  scope                = azurerm_key_vault.this[0].id
  role_definition_name = "Key Vault Administrator"
  principal_id         = each.value
  description          = "Key Vault data-plane administrators."
}

resource "azurerm_monitor_diagnostic_setting" "kv" {
  count = var.key_vault.enabled ? 1 : 0

  name                       = "diag-to-law"
  target_resource_id         = azurerm_key_vault.this[0].id
  log_analytics_workspace_id = local.law_id

  enabled_log {
    category_group = "audit"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

###############################################################################
# Private endpoints + private DNS
###############################################################################

resource "azurerm_private_dns_zone" "this" {
  for_each = local.created_dns_zones

  name                = each.value.zone_name
  resource_group_name = var.resource_group_name
  tags                = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "this" {
  for_each = local.created_dns_zones

  name                 = "link-${var.name}-${each.key}"
  private_dns_zone_id  = azurerm_private_dns_zone.this[each.key].id
  virtual_network_id   = var.private_endpoints.vnet_id
  registration_enabled = false
  tags                 = local.tags
}

resource "azurerm_private_endpoint" "this" {
  for_each = local.private_endpoints

  name                          = "pe-${var.name}-${each.key}"
  location                      = var.location
  resource_group_name           = var.resource_group_name
  subnet_id                     = var.private_endpoints.subnet_id
  custom_network_interface_name = "nic-pe-${var.name}-${each.key}"
  tags                          = local.tags

  private_service_connection {
    name                           = "psc-${var.name}-${each.key}"
    private_connection_resource_id = each.value.resource_id
    subresource_names              = [each.value.subresource]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name = "default"
    private_dns_zone_ids = [
      var.private_endpoints.create_dns_zones ? azurerm_private_dns_zone.this[each.key].id : var.private_endpoints.dns_zone_ids[each.key]
    ]
  }
}
