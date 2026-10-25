# Unit tests for modules/azure-aks.
# mock_provider: the azurerm provider schema is used, but no Azure API is called.

mock_provider "azurerm" {
  mock_data "azurerm_client_config" {
    defaults = {
      tenant_id       = "00000000-0000-0000-0000-000000000001"
      subscription_id = "00000000-0000-0000-0000-000000000002"
      object_id       = "00000000-0000-0000-0000-000000000003"
    }
  }
}

variables {
  name                = "unit"
  location            = "westeurope"
  resource_group_name = "rg-unit"
  vnet_subnet_id      = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-unit/providers/Microsoft.Network/virtualNetworks/vnet-unit/subnets/aks-nodes"
  tags = {
    environment = "test"
  }
  user_node_pools = {
    apps = {
      vm_size   = "Standard_D4ds_v5"
      min_count = 1
      max_count = 10
    }
    batch = {
      vm_size   = "Standard_D8ds_v5"
      max_count = 20
      priority  = "Spot"
    }
  }
}

run "secure_defaults" {
  command = plan

  assert {
    condition     = azurerm_kubernetes_cluster.this.private_cluster_enabled == true
    error_message = "Clusters must be private by default."
  }

  assert {
    condition     = length(azurerm_kubernetes_cluster.this.api_server_access_profile) == 0
    error_message = "Private clusters must not set authorized IP ranges."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.local_account_disabled == true && azurerm_kubernetes_cluster.this.azure_active_directory_role_based_access_control[0].azure_rbac_enabled == true
    error_message = "Local accounts must be disabled and Azure RBAC enabled."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.oidc_issuer_enabled && azurerm_kubernetes_cluster.this.workload_identity_enabled
    error_message = "OIDC issuer and Workload Identity must be enabled by default."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.azure_policy_enabled == true
    error_message = "Azure Policy add-on must be on by default."
  }

  assert {
    condition     = length(azurerm_kubernetes_cluster.this.microsoft_defender) == 0
    error_message = "Defender is opt-in (billed) and must be off by default."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.sku_tier == "Standard" && azurerm_kubernetes_cluster.this.run_command_enabled == false
    error_message = "Expected Standard tier and run command disabled."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.key_vault_secrets_provider[0].secret_rotation_enabled == true
    error_message = "Secrets Store CSI driver must rotate secrets."
  }
}

run "network_profile_overlay_cilium" {
  command = plan

  assert {
    condition     = azurerm_kubernetes_cluster.this.network_profile[0].network_plugin == "azure" && azurerm_kubernetes_cluster.this.network_profile[0].network_plugin_mode == "overlay"
    error_message = "Default must be Azure CNI Overlay."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.network_profile[0].network_policy == "cilium" && azurerm_kubernetes_cluster.this.network_profile[0].network_data_plane == "cilium"
    error_message = "Default network policy / data plane must be Cilium."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.network_profile[0].dns_service_ip == "172.16.0.10"
    error_message = "DNS service IP must be derived from service_cidr."
  }
}

run "classic_cni_with_pod_subnet" {
  command = plan

  variables {
    network_plugin_mode = null
    pod_subnet_id       = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-unit/providers/Microsoft.Network/virtualNetworks/vnet-unit/subnets/aks-pods"
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.network_profile[0].network_plugin_mode == null
    error_message = "Classic Azure CNI must not set overlay mode."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.default_node_pool[0].pod_subnet_id == var.pod_subnet_id
    error_message = "pod_subnet_id must be wired to the system pool for classic CNI."
  }
}

run "system_pool_autoscaling_bounds" {
  command = plan

  variables {
    system_node_pool = {
      min_count = 3
      max_count = 6
    }
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.default_node_pool[0].auto_scaling_enabled == true
    error_message = "System pool must be autoscaled."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.default_node_pool[0].min_count == 3 && azurerm_kubernetes_cluster.this.default_node_pool[0].max_count == 6
    error_message = "System pool autoscaler bounds not applied."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.default_node_pool[0].only_critical_addons_enabled == true
    error_message = "System pool must be tainted for critical add-ons only."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.default_node_pool[0].node_public_ip_enabled == false
    error_message = "Nodes must not get public IPs."
  }
}

run "user_pools_autoscaling_and_spot" {
  command = plan

  assert {
    condition     = length(azurerm_kubernetes_cluster_node_pool.user) == 2
    error_message = "Expected two user node pools."
  }

  assert {
    condition     = azurerm_kubernetes_cluster_node_pool.user["apps"].auto_scaling_enabled && azurerm_kubernetes_cluster_node_pool.user["apps"].min_count == 1 && azurerm_kubernetes_cluster_node_pool.user["apps"].max_count == 10
    error_message = "apps pool autoscaler bounds not applied."
  }

  assert {
    condition     = azurerm_kubernetes_cluster_node_pool.user["batch"].min_count == 0 && azurerm_kubernetes_cluster_node_pool.user["batch"].max_count == 20
    error_message = "batch pool must scale from zero to 20."
  }

  assert {
    condition     = azurerm_kubernetes_cluster_node_pool.user["batch"].eviction_policy == "Delete" && contains(azurerm_kubernetes_cluster_node_pool.user["batch"].node_taints, "kubernetes.azure.com/scalesetpriority=spot:NoSchedule")
    error_message = "Spot pool must use Delete eviction and carry the spot taint."
  }

  assert {
    condition     = length(azurerm_kubernetes_cluster_node_pool.user["batch"].upgrade_settings) == 0 && azurerm_kubernetes_cluster_node_pool.user["apps"].upgrade_settings[0].max_surge == "33%"
    error_message = "Surge settings must be set on regular pools and omitted on Spot pools."
  }
}

run "rejects_inverted_autoscaling_bounds" {
  command = plan

  variables {
    system_node_pool = {
      min_count = 5
      max_count = 2
    }
  }

  expect_failures = [var.system_node_pool]
}

run "rejects_inverted_user_pool_bounds" {
  command = plan

  variables {
    user_node_pools = {
      bad = {
        vm_size   = "Standard_D4ds_v5"
        min_count = 4
        max_count = 2
      }
    }
  }

  expect_failures = [var.user_node_pools]
}

run "public_cluster_requires_authorized_ranges" {
  command = plan

  variables {
    private_cluster_enabled = false
  }

  expect_failures = [var.api_server_authorized_ip_ranges]
}

run "public_cluster_with_authorized_ranges" {
  command = plan

  variables {
    private_cluster_enabled         = false
    api_server_authorized_ip_ranges = ["203.0.113.0/24"]
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.private_cluster_enabled == false && azurerm_kubernetes_cluster.this.api_server_access_profile[0].authorized_ip_ranges == toset(["203.0.113.0/24"])
    error_message = "Public cluster must be locked to the authorized ranges."
  }
}

run "rejects_open_authorized_range" {
  command = plan

  variables {
    private_cluster_enabled         = false
    api_server_authorized_ip_ranges = ["0.0.0.0/0"]
  }

  expect_failures = [var.api_server_authorized_ip_ranges]
}

run "rejects_cilium_mismatch" {
  command = plan

  variables {
    network_data_plane = "azure"
    network_policy     = "cilium"
  }

  expect_failures = [var.network_policy]
}

run "toggles_policy_and_defender" {
  command = plan

  variables {
    azure_policy_enabled = false
    defender_enabled     = true
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.azure_policy_enabled == false
    error_message = "azure_policy_enabled toggle ignored."
  }

  assert {
    condition     = length(azurerm_kubernetes_cluster.this.microsoft_defender) == 1
    error_message = "defender_enabled toggle ignored."
  }
}

run "acr_integration" {
  command = plan

  assert {
    condition     = azurerm_container_registry.this[0].admin_enabled == false && azurerm_container_registry.this[0].anonymous_pull_enabled == false
    error_message = "ACR admin user and anonymous pull must be disabled."
  }

  assert {
    condition     = azurerm_container_registry.this[0].name == "acrunit" && azurerm_container_registry.this[0].sku == "Premium"
    error_message = "ACR name/sku defaults unexpected."
  }

  assert {
    condition     = azurerm_role_assignment.kubelet_acr_pull[0].role_definition_name == "AcrPull"
    error_message = "Kubelet identity must get AcrPull on the registry."
  }
}

run "key_vault_rbac_and_hardening" {
  command = plan

  variables {
    key_vault = {
      admin_principal_ids = ["00000000-0000-0000-0000-00000000000a"]
    }
  }

  assert {
    condition     = azurerm_key_vault.this[0].rbac_authorization_enabled == true
    error_message = "Key Vault must use RBAC authorization."
  }

  assert {
    condition     = azurerm_key_vault.this[0].purge_protection_enabled == true && azurerm_key_vault.this[0].network_acls[0].default_action == "Deny"
    error_message = "Key Vault must have purge protection and a default-deny firewall."
  }

  assert {
    condition     = azurerm_role_assignment.kv_secrets_provider[0].role_definition_name == "Key Vault Secrets User" && length(azurerm_role_assignment.kv_admins) == 1
    error_message = "Expected the CSI driver reader role and one admin role assignment."
  }
}

run "private_endpoints_disable_public_access" {
  command = plan

  variables {
    private_endpoints = {
      enabled   = true
      subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-unit/providers/Microsoft.Network/virtualNetworks/vnet-unit/subnets/private-endpoints"
      vnet_id   = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-unit/providers/Microsoft.Network/virtualNetworks/vnet-unit"
    }
  }

  assert {
    condition     = length(azurerm_private_endpoint.this) == 2 && length(azurerm_private_dns_zone.this) == 2
    error_message = "Expected private endpoints and DNS zones for ACR and Key Vault."
  }

  assert {
    condition     = azurerm_private_dns_zone.this["key_vault"].name == "privatelink.vaultcore.azure.net" && azurerm_private_dns_zone.this["acr"].name == "privatelink.azurecr.io"
    error_message = "Wrong privatelink zone names."
  }

  assert {
    condition     = azurerm_key_vault.this[0].public_network_access_enabled == false && azurerm_container_registry.this[0].public_network_access_enabled == false
    error_message = "Public network access must be disabled once private endpoints exist."
  }

  assert {
    condition     = azurerm_container_registry.this[0].export_policy_enabled == false
    error_message = "Image export must be blocked on a private Premium registry."
  }
}

run "private_endpoints_byo_dns" {
  command = plan

  variables {
    private_endpoints = {
      enabled          = true
      subnet_id        = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-unit/providers/Microsoft.Network/virtualNetworks/vnet-unit/subnets/private-endpoints"
      create_dns_zones = false
      dns_zone_ids = {
        acr       = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-hub/providers/Microsoft.Network/privateDnsZones/privatelink.azurecr.io"
        key_vault = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-hub/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net"
      }
    }
  }

  assert {
    condition     = length(azurerm_private_dns_zone.this) == 0 && length(azurerm_private_endpoint.this) == 2
    error_message = "Hub-and-spoke mode must reuse existing zones."
  }
}

run "diagnostics_to_log_analytics" {
  command = plan

  assert {
    condition     = length(azurerm_log_analytics_workspace.this) == 1 && azurerm_log_analytics_workspace.this[0].local_authentication_enabled == false
    error_message = "Module must create a workspace with shared-key auth disabled."
  }

  assert {
    condition     = contains([for l in azurerm_monitor_diagnostic_setting.aks.enabled_log : l.category], "kube-audit-admin")
    error_message = "AKS audit logs must be shipped."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.oms_agent[0].msi_auth_for_monitoring_enabled == true
    error_message = "Container Insights must use managed identity auth."
  }
}

run "byo_log_analytics" {
  command = plan

  variables {
    create_log_analytics_workspace = false
    log_analytics_workspace_id     = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-mgmt/providers/Microsoft.OperationalInsights/workspaces/law-central"
  }

  assert {
    condition     = length(azurerm_log_analytics_workspace.this) == 0
    error_message = "No workspace must be created when one is supplied."
  }

  assert {
    condition     = azurerm_monitor_diagnostic_setting.aks.log_analytics_workspace_id == var.log_analytics_workspace_id
    error_message = "Diagnostics must target the supplied workspace."
  }
}

run "byo_log_analytics_requires_id" {
  command = plan

  variables {
    create_log_analytics_workspace = false
  }

  expect_failures = [var.log_analytics_workspace_id]
}

run "tags_applied" {
  command = plan

  assert {
    condition     = azurerm_kubernetes_cluster.this.tags["environment"] == "test" && azurerm_kubernetes_cluster.this.tags["managed-by"] == "terraform"
    error_message = "Tags must be applied to the cluster."
  }

  assert {
    condition     = alltrue([for p in azurerm_kubernetes_cluster_node_pool.user : p.tags["environment"] == "test"])
    error_message = "Tags must be applied to user node pools."
  }

  assert {
    condition     = azurerm_key_vault.this[0].tags["environment"] == "test" && azurerm_container_registry.this[0].tags["environment"] == "test"
    error_message = "Tags must be applied to ACR and Key Vault."
  }
}
