data "azurerm_client_config" "current" {}

locals {
  tags = merge(var.tags, { "managed-by" = "terraform", "module" = "azure-aks" })

  compact_name = replace(var.name, "-", "")
  acr_name     = coalesce(var.acr.name, substr("acr${local.compact_name}", 0, 50))
  kv_name      = coalesce(var.key_vault.name, substr("kv-${var.name}", 0, 24))

  law_id = var.create_log_analytics_workspace ? azurerm_log_analytics_workspace.this[0].id : var.log_analytics_workspace_id

  custom_private_dns_zone = var.private_cluster_enabled && !contains(["System", "None"], var.private_dns_zone_id)
  acr_premium             = var.acr.sku == "Premium"

  # Private endpoint targets. Keys are static so for_each works even though IDs are unknown at plan time.
  private_endpoint_targets = merge(
    var.acr.enabled ? {
      acr = {
        resource_id = one(azurerm_container_registry.this[*].id)
        subresource = "registry"
        zone_name   = "privatelink.azurecr.io"
      }
    } : {},
    var.key_vault.enabled ? {
      key_vault = {
        resource_id = one(azurerm_key_vault.this[*].id)
        subresource = "vault"
        zone_name   = "privatelink.vaultcore.azure.net"
      }
    } : {},
  )
  private_endpoints = var.private_endpoints.enabled ? local.private_endpoint_targets : {}
  created_dns_zones = var.private_endpoints.enabled && var.private_endpoints.create_dns_zones ? local.private_endpoint_targets : {}

  maintenance = {
    frequency   = "Weekly"
    interval    = 1
    duration    = var.maintenance_window.duration_hours
    day_of_week = var.maintenance_window.day_of_week
    start_time  = var.maintenance_window.start_time
    utc_offset  = "+00:00"
  }

  pod_subnet_id = var.network_plugin_mode == null ? var.pod_subnet_id : null
}

###############################################################################
# Identities
# User-assigned identities survive cluster re-creation, so role assignments
# (subnet, ACR, DNS zone) do not have to be rebuilt with the cluster.
###############################################################################

resource "azurerm_user_assigned_identity" "control_plane" {
  name                = "id-${var.name}-control-plane"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = local.tags
}

resource "azurerm_user_assigned_identity" "kubelet" {
  name                = "id-${var.name}-kubelet"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = local.tags
}

resource "azurerm_role_assignment" "control_plane_network" {
  scope                = var.vnet_subnet_id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.control_plane.principal_id
  principal_type       = "ServicePrincipal"
  description          = "AKS control plane manages load balancers / IPs in the node subnet."
}

resource "azurerm_role_assignment" "control_plane_kubelet_operator" {
  scope                = azurerm_user_assigned_identity.kubelet.id
  role_definition_name = "Managed Identity Operator"
  principal_id         = azurerm_user_assigned_identity.control_plane.principal_id
  principal_type       = "ServicePrincipal"
  description          = "AKS control plane assigns the kubelet identity to node VMSS."
}

resource "azurerm_role_assignment" "control_plane_private_dns" {
  count = local.custom_private_dns_zone ? 1 : 0

  scope                = var.private_dns_zone_id
  role_definition_name = "Private DNS Zone Contributor"
  principal_id         = azurerm_user_assigned_identity.control_plane.principal_id
  principal_type       = "ServicePrincipal"
  description          = "AKS control plane writes the API server A record into the BYO private zone."
}

###############################################################################
# Log Analytics
###############################################################################

resource "azurerm_log_analytics_workspace" "this" {
  count = var.create_log_analytics_workspace ? 1 : 0

  name                         = "law-${var.name}"
  location                     = var.location
  resource_group_name          = var.resource_group_name
  sku                          = "PerGB2018"
  retention_in_days            = var.log_retention_days
  local_authentication_enabled = false
  tags                         = local.tags
}

###############################################################################
# AKS cluster
###############################################################################

resource "azurerm_kubernetes_cluster" "this" {
  name                = "aks-${var.name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  node_resource_group = "rg-${var.name}-nodes"

  dns_prefix                 = local.custom_private_dns_zone ? null : var.name
  dns_prefix_private_cluster = local.custom_private_dns_zone ? var.name : null

  kubernetes_version        = var.kubernetes_version
  sku_tier                  = var.sku_tier
  automatic_upgrade_channel = var.automatic_upgrade_channel == "none" ? null : var.automatic_upgrade_channel
  node_os_upgrade_channel   = var.node_os_upgrade_channel

  private_cluster_enabled             = var.private_cluster_enabled
  private_dns_zone_id                 = var.private_cluster_enabled ? var.private_dns_zone_id : null
  private_cluster_public_fqdn_enabled = false

  local_account_disabled            = true
  role_based_access_control_enabled = true
  oidc_issuer_enabled               = true
  workload_identity_enabled         = var.workload_identity_enabled
  azure_policy_enabled              = var.azure_policy_enabled
  run_command_enabled               = var.run_command_enabled
  image_cleaner_enabled             = true
  image_cleaner_interval_hours      = var.image_cleaner_interval_hours
  disk_encryption_set_id            = var.disk_encryption_set_id

  dynamic "api_server_access_profile" {
    for_each = var.private_cluster_enabled ? [] : [1]
    content {
      authorized_ip_ranges = var.api_server_authorized_ip_ranges
    }
  }

  azure_active_directory_role_based_access_control {
    azure_rbac_enabled     = true
    tenant_id              = data.azurerm_client_config.current.tenant_id
    admin_group_object_ids = var.admin_group_object_ids
  }

  default_node_pool {
    name                         = var.system_node_pool.name
    temporary_name_for_rotation  = "${substr(var.system_node_pool.name, 0, 9)}tmp"
    vm_size                      = var.system_node_pool.vm_size
    vnet_subnet_id               = var.vnet_subnet_id
    pod_subnet_id                = local.pod_subnet_id
    zones                        = var.system_node_pool.zones
    only_critical_addons_enabled = true
    auto_scaling_enabled         = true
    min_count                    = var.system_node_pool.min_count
    max_count                    = var.system_node_pool.max_count
    max_pods                     = var.system_node_pool.max_pods
    os_sku                       = var.system_node_pool.os_sku
    os_disk_type                 = var.system_node_pool.os_disk_type
    os_disk_size_gb              = var.system_node_pool.os_disk_size_gb
    host_encryption_enabled      = var.host_encryption_enabled
    node_public_ip_enabled       = false
    tags                         = local.tags

    upgrade_settings {
      max_surge = var.system_node_pool.max_surge
    }
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.control_plane.id]
  }

  kubelet_identity {
    client_id                 = azurerm_user_assigned_identity.kubelet.client_id
    object_id                 = azurerm_user_assigned_identity.kubelet.principal_id
    user_assigned_identity_id = azurerm_user_assigned_identity.kubelet.id
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = var.network_plugin_mode
    network_data_plane  = var.network_data_plane
    network_policy      = var.network_policy
    pod_cidr            = var.network_plugin_mode == "overlay" ? var.pod_cidr : null
    service_cidr        = var.service_cidr
    dns_service_ip      = cidrhost(var.service_cidr, 10)
    outbound_type       = var.outbound_type
    load_balancer_sku   = "standard"
  }

  # Classic cluster autoscaler on explicit node pools (not Node Auto Provisioning / Karpenter).
  node_provisioning_profile {
    mode = "Manual"
  }

  auto_scaler_profile {
    expander                         = var.auto_scaler_profile.expander
    balance_similar_node_groups      = var.auto_scaler_profile.balance_similar_node_groups
    scale_down_unneeded              = var.auto_scaler_profile.scale_down_unneeded
    scale_down_utilization_threshold = var.auto_scaler_profile.scale_down_utilization_threshold
    max_unready_percentage           = var.auto_scaler_profile.max_unready_percentage
    skip_nodes_with_system_pods      = true
  }

  oms_agent {
    log_analytics_workspace_id      = local.law_id
    msi_auth_for_monitoring_enabled = true
  }

  dynamic "microsoft_defender" {
    for_each = var.defender_enabled ? [1] : []
    content {
      log_analytics_workspace_id = local.law_id
    }
  }

  key_vault_secrets_provider {
    secret_rotation_enabled  = true
    secret_rotation_interval = "2m"
  }

  maintenance_window_auto_upgrade {
    frequency   = local.maintenance.frequency
    interval    = local.maintenance.interval
    duration    = local.maintenance.duration
    day_of_week = local.maintenance.day_of_week
    start_time  = local.maintenance.start_time
    utc_offset  = local.maintenance.utc_offset
  }

  maintenance_window_node_os {
    frequency   = local.maintenance.frequency
    interval    = local.maintenance.interval
    duration    = local.maintenance.duration
    day_of_week = local.maintenance.day_of_week
    start_time  = local.maintenance.start_time
    utc_offset  = local.maintenance.utc_offset
  }

  tags = local.tags

  lifecycle {
    # The cluster autoscaler owns node_count once the pool exists.
    ignore_changes = [default_node_pool[0].node_count]

    precondition {
      condition     = var.automatic_upgrade_channel != "node-image" || var.node_os_upgrade_channel == "NodeImage"
      error_message = "automatic_upgrade_channel = node-image requires node_os_upgrade_channel = NodeImage."
    }

    precondition {
      condition     = var.network_plugin_mode == "overlay" || var.network_data_plane != "cilium" || var.pod_subnet_id != null
      error_message = "Cilium data plane with classic Azure CNI needs a dedicated pod_subnet_id."
    }
  }

  depends_on = [
    azurerm_role_assignment.control_plane_network,
    azurerm_role_assignment.control_plane_kubelet_operator,
    azurerm_role_assignment.control_plane_private_dns,
  ]
}

resource "azurerm_kubernetes_cluster_node_pool" "user" {
  for_each = var.user_node_pools

  name                        = each.key
  temporary_name_for_rotation = "${substr(each.key, 0, 9)}tmp"
  kubernetes_cluster_id       = azurerm_kubernetes_cluster.this.id
  mode                        = "User"
  vm_size                     = each.value.vm_size
  vnet_subnet_id              = var.vnet_subnet_id
  pod_subnet_id               = local.pod_subnet_id
  zones                       = each.value.zones
  auto_scaling_enabled        = true
  min_count                   = each.value.min_count
  max_count                   = each.value.max_count
  max_pods                    = each.value.max_pods
  os_type                     = "Linux"
  os_sku                      = each.value.os_sku
  os_disk_type                = each.value.os_disk_type
  os_disk_size_gb             = each.value.os_disk_size_gb
  host_encryption_enabled     = var.host_encryption_enabled
  node_public_ip_enabled      = false
  priority                    = each.value.priority
  eviction_policy             = each.value.priority == "Spot" ? "Delete" : null
  spot_max_price              = each.value.priority == "Spot" ? each.value.spot_max_price : null
  node_labels                 = each.value.node_labels
  # AKS always adds this taint to Spot pools; declaring it avoids a perpetual diff.
  node_taints = each.value.priority == "Spot" ? distinct(concat(each.value.node_taints, ["kubernetes.azure.com/scalesetpriority=spot:NoSchedule"])) : each.value.node_taints
  tags        = local.tags

  # Surge upgrades are not supported on Spot pools.
  dynamic "upgrade_settings" {
    for_each = each.value.priority == "Spot" ? [] : [1]
    content {
      max_surge = each.value.max_surge
    }
  }

  lifecycle {
    ignore_changes = [node_count]
  }
}

###############################################################################
# Diagnostics
###############################################################################

resource "azurerm_monitor_diagnostic_setting" "aks" {
  name                           = "diag-to-law"
  target_resource_id             = azurerm_kubernetes_cluster.this.id
  log_analytics_workspace_id     = local.law_id
  log_analytics_destination_type = "Dedicated"

  dynamic "enabled_log" {
    for_each = toset(var.cluster_log_categories)
    content {
      category = enabled_log.value
    }
  }

  enabled_metric {
    category = "AllMetrics"
  }
}
