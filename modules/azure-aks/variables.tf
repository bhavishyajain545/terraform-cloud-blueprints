###############################################################################
# General
###############################################################################

variable "name" {
  description = "Cluster name (also used to derive names of the ACR, Key Vault, identities and workspace)."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,30}[a-z0-9]$", var.name))
    error_message = "name must be 3-32 characters of lowercase letters, digits and hyphens."
  }
}

variable "location" {
  description = "Azure region, e.g. \"westeurope\"."
  type        = string
}

variable "resource_group_name" {
  description = "Existing resource group for the cluster and its supporting resources."
  type        = string
}

variable "tags" {
  description = "Tags applied to every resource created by this module."
  type        = map(string)
  default     = {}
}

###############################################################################
# Control plane
###############################################################################

variable "kubernetes_version" {
  description = "Kubernetes minor version (e.g. \"1.34\"). null lets AKS pick the default; patch upgrades follow automatic_upgrade_channel."
  type        = string
  default     = null

  validation {
    condition     = var.kubernetes_version == null || can(regex("^1\\.[0-9]{2}$", var.kubernetes_version))
    error_message = "kubernetes_version must be a minor version like \"1.34\" (patch versions are managed by the upgrade channel)."
  }
}

variable "sku_tier" {
  description = "AKS control plane tier. Standard gives the uptime SLA; Free is only for throw-away clusters."
  type        = string
  default     = "Standard"

  validation {
    condition     = contains(["Free", "Standard", "Premium"], var.sku_tier)
    error_message = "sku_tier must be Free, Standard or Premium."
  }
}

variable "automatic_upgrade_channel" {
  description = "Cluster auto-upgrade channel."
  type        = string
  default     = "patch"

  validation {
    condition     = contains(["none", "patch", "stable", "rapid", "node-image"], var.automatic_upgrade_channel)
    error_message = "automatic_upgrade_channel must be one of none, patch, stable, rapid, node-image."
  }
}

variable "node_os_upgrade_channel" {
  description = "Node OS image upgrade channel."
  type        = string
  default     = "NodeImage"

  validation {
    condition     = contains(["None", "Unmanaged", "SecurityPatch", "NodeImage"], var.node_os_upgrade_channel)
    error_message = "node_os_upgrade_channel must be one of None, Unmanaged, SecurityPatch, NodeImage."
  }
}

variable "maintenance_window" {
  description = "Weekly window (UTC) used for both cluster and node OS auto-upgrades."
  type = object({
    day_of_week    = optional(string, "Sunday")
    start_time     = optional(string, "02:00")
    duration_hours = optional(number, 4)
  })
  default = {}

  validation {
    condition     = contains(["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"], var.maintenance_window.day_of_week)
    error_message = "maintenance_window.day_of_week must be a weekday name, e.g. \"Sunday\"."
  }

  validation {
    condition     = can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", var.maintenance_window.start_time)) && var.maintenance_window.duration_hours >= 4 && var.maintenance_window.duration_hours <= 24
    error_message = "maintenance_window.start_time must be HH:MM and duration_hours between 4 and 24."
  }
}

variable "private_cluster_enabled" {
  description = "Expose the API server only on a private endpoint inside the VNet."
  type        = bool
  default     = true
}

variable "private_dns_zone_id" {
  description = "Private DNS zone for the private API server: \"System\" (AKS-managed), \"None\", or the ID of a zone you own (hub-and-spoke)."
  type        = string
  default     = "System"
}

variable "api_server_authorized_ip_ranges" {
  description = "CIDRs allowed to reach a *public* API server. Ignored for private clusters. Must be non-empty for public clusters."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for c in var.api_server_authorized_ip_ranges : can(cidrhost(c, 0)) && c != "0.0.0.0/0"])
    error_message = "api_server_authorized_ip_ranges must be valid CIDRs and must not contain 0.0.0.0/0."
  }

  validation {
    condition     = var.private_cluster_enabled || length(var.api_server_authorized_ip_ranges) > 0
    error_message = "A public cluster (private_cluster_enabled = false) needs at least one api_server_authorized_ip_ranges entry."
  }
}

variable "admin_group_object_ids" {
  description = "Entra ID group object IDs granted cluster-admin through Azure RBAC for Kubernetes."
  type        = list(string)
  default     = []
}

variable "run_command_enabled" {
  description = "Allow `az aks command invoke`. Handy for private clusters without a jump host, but it is an extra control-plane entry point."
  type        = bool
  default     = false
}

###############################################################################
# Networking
###############################################################################

variable "vnet_subnet_id" {
  description = "Subnet ID for the node pools (and the API server VNet integration, if used)."
  type        = string
}

variable "network_plugin_mode" {
  description = "\"overlay\" (Azure CNI Overlay: pods get IPs from pod_cidr, saves VNet space) or null for classic Azure CNI (pods get VNet IPs)."
  type        = string
  default     = "overlay"

  validation {
    condition     = var.network_plugin_mode == null || var.network_plugin_mode == "overlay"
    error_message = "network_plugin_mode must be \"overlay\" or null."
  }
}

variable "network_data_plane" {
  description = "Data plane: \"cilium\" (eBPF, Cilium network policy) or \"azure\"."
  type        = string
  default     = "cilium"

  validation {
    condition     = contains(["azure", "cilium"], var.network_data_plane)
    error_message = "network_data_plane must be azure or cilium."
  }
}

variable "network_policy" {
  description = "Network policy engine. Must be \"cilium\" when network_data_plane is cilium."
  type        = string
  default     = "cilium"

  validation {
    condition     = contains(["azure", "calico", "cilium"], var.network_policy)
    error_message = "network_policy must be azure, calico or cilium."
  }

  validation {
    condition     = (var.network_data_plane == "cilium") == (var.network_policy == "cilium")
    error_message = "network_policy must be \"cilium\" if and only if network_data_plane is \"cilium\"."
  }
}

variable "pod_cidr" {
  description = "Pod CIDR for Azure CNI Overlay. Must not overlap the VNet or service_cidr."
  type        = string
  default     = "10.244.0.0/16"

  validation {
    condition     = can(cidrhost(var.pod_cidr, 0))
    error_message = "pod_cidr must be a valid CIDR."
  }
}

variable "pod_subnet_id" {
  description = "Dedicated pod subnet for classic Azure CNI with dynamic IP allocation. Only used when network_plugin_mode is null."
  type        = string
  default     = null
}

variable "service_cidr" {
  description = "Kubernetes service CIDR. Must not overlap the VNet or pod_cidr."
  type        = string
  default     = "172.16.0.0/16"

  validation {
    condition     = can(cidrhost(var.service_cidr, 10))
    error_message = "service_cidr must be a valid CIDR with room for the DNS service IP."
  }
}

variable "outbound_type" {
  description = "Egress path for nodes. Use userDefinedRouting behind an Azure Firewall/NVA in hub-and-spoke."
  type        = string
  default     = "loadBalancer"

  validation {
    condition     = contains(["loadBalancer", "userDefinedRouting", "managedNATGateway", "userAssignedNATGateway"], var.outbound_type)
    error_message = "outbound_type must be loadBalancer, userDefinedRouting, managedNATGateway or userAssignedNATGateway."
  }
}

###############################################################################
# Node pools
###############################################################################

variable "system_node_pool" {
  description = "System node pool (critical add-ons only). Autoscaled between min_count and max_count."
  type = object({
    name            = optional(string, "system")
    vm_size         = optional(string, "Standard_D4ds_v5")
    min_count       = optional(number, 2)
    max_count       = optional(number, 5)
    max_pods        = optional(number, 110)
    os_sku          = optional(string, "AzureLinux")
    os_disk_type    = optional(string, "Ephemeral")
    os_disk_size_gb = optional(number, 128)
    zones           = optional(list(string), ["1", "2", "3"])
    max_surge       = optional(string, "33%")
  })
  default = {}

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{0,11}$", var.system_node_pool.name))
    error_message = "system_node_pool.name must be 1-12 lowercase alphanumerics starting with a letter."
  }

  validation {
    condition     = var.system_node_pool.min_count >= 1 && var.system_node_pool.min_count <= var.system_node_pool.max_count && var.system_node_pool.max_count <= 1000
    error_message = "system_node_pool must satisfy 1 <= min_count <= max_count <= 1000."
  }

  validation {
    condition     = var.system_node_pool.max_pods >= 30 && var.system_node_pool.max_pods <= 250
    error_message = "system_node_pool.max_pods must be between 30 and 250."
  }

  validation {
    condition     = contains(["Ephemeral", "Managed"], var.system_node_pool.os_disk_type) && contains(["AzureLinux", "Ubuntu"], var.system_node_pool.os_sku)
    error_message = "system_node_pool.os_disk_type must be Ephemeral or Managed; os_sku must be AzureLinux or Ubuntu."
  }
}

variable "user_node_pools" {
  description = "Additional user node pools keyed by pool name (1-12 lowercase alphanumerics). Each is autoscaled between min_count and max_count."
  type = map(object({
    vm_size         = string
    min_count       = optional(number, 0)
    max_count       = number
    max_pods        = optional(number, 110)
    os_sku          = optional(string, "AzureLinux")
    os_disk_type    = optional(string, "Ephemeral")
    os_disk_size_gb = optional(number, 128)
    zones           = optional(list(string), ["1", "2", "3"])
    priority        = optional(string, "Regular")
    spot_max_price  = optional(number, -1)
    node_labels     = optional(map(string), {})
    node_taints     = optional(list(string), [])
    max_surge       = optional(string, "33%")
  }))
  default = {}

  validation {
    condition     = alltrue([for k in keys(var.user_node_pools) : can(regex("^[a-z][a-z0-9]{0,11}$", k))])
    error_message = "user_node_pools keys must be 1-12 lowercase alphanumerics starting with a letter."
  }

  validation {
    condition     = alltrue([for p in values(var.user_node_pools) : p.min_count >= 0 && p.min_count <= p.max_count && p.max_count >= 1 && p.max_count <= 1000])
    error_message = "Each user node pool must satisfy 0 <= min_count <= max_count, 1 <= max_count <= 1000."
  }

  validation {
    condition     = alltrue([for p in values(var.user_node_pools) : contains(["Regular", "Spot"], p.priority)])
    error_message = "user_node_pools[*].priority must be Regular or Spot."
  }
}

variable "auto_scaler_profile" {
  description = "Cluster autoscaler tuning shared by all pools."
  type = object({
    expander                         = optional(string, "least-waste")
    balance_similar_node_groups      = optional(bool, true)
    scale_down_unneeded              = optional(string, "10m")
    scale_down_utilization_threshold = optional(string, "0.5")
    max_unready_percentage           = optional(number, 45)
  })
  default = {}

  validation {
    condition     = contains(["least-waste", "most-pods", "priority", "random"], var.auto_scaler_profile.expander)
    error_message = "auto_scaler_profile.expander must be least-waste, most-pods, priority or random."
  }
}

variable "host_encryption_enabled" {
  description = "Encrypt node temp disks, caches and OS/data disk flows at the VM host. Requires the Microsoft.Compute/EncryptionAtHost feature to be registered on the subscription once."
  type        = bool
  default     = true
}

variable "disk_encryption_set_id" {
  description = "Disk Encryption Set for customer-managed-key encryption of node OS/data disks. null = platform-managed keys."
  type        = string
  default     = null
}

###############################################################################
# Add-ons and security features
###############################################################################

variable "workload_identity_enabled" {
  description = "Enable Entra Workload ID (also enables the OIDC issuer). Pods federate to managed identities instead of using secrets."
  type        = bool
  default     = true
}

variable "azure_policy_enabled" {
  description = "Install the Azure Policy add-on (Gatekeeper) so policy assignments are enforced in-cluster."
  type        = bool
  default     = true
}

variable "defender_enabled" {
  description = "Enable Microsoft Defender for Containers sensor (billed per vCore)."
  type        = bool
  default     = false
}

variable "image_cleaner_interval_hours" {
  description = "Interval for the Image Cleaner (Eraser) that removes unused, vulnerable images from nodes."
  type        = number
  default     = 48

  validation {
    condition     = var.image_cleaner_interval_hours >= 24 && var.image_cleaner_interval_hours <= 2160
    error_message = "image_cleaner_interval_hours must be between 24 and 2160."
  }
}

###############################################################################
# Observability
###############################################################################

variable "create_log_analytics_workspace" {
  description = "Create a Log Analytics workspace. Set false and pass log_analytics_workspace_id to use a central one."
  type        = bool
  default     = true
}

variable "log_analytics_workspace_id" {
  description = "Existing Log Analytics workspace ID (required when create_log_analytics_workspace = false)."
  type        = string
  default     = null

  validation {
    condition     = var.create_log_analytics_workspace || var.log_analytics_workspace_id != null
    error_message = "log_analytics_workspace_id is required when create_log_analytics_workspace = false."
  }
}

variable "log_retention_days" {
  description = "Retention of the module-created Log Analytics workspace."
  type        = number
  default     = 30

  validation {
    condition     = var.log_retention_days >= 30 && var.log_retention_days <= 730
    error_message = "log_retention_days must be between 30 and 730."
  }
}

variable "cluster_log_categories" {
  description = "AKS resource log categories sent to Log Analytics. kube-audit-admin is audit without the noisy get/list events."
  type        = list(string)
  default     = ["kube-apiserver", "kube-audit-admin", "kube-controller-manager", "kube-scheduler", "cluster-autoscaler", "guard"]
}

###############################################################################
# ACR
###############################################################################

variable "acr" {
  description = "Azure Container Registry created for the cluster. The kubelet identity gets AcrPull. Premium is required for private endpoints and retention policy."
  type = object({
    enabled                 = optional(bool, true)
    name                    = optional(string)
    sku                     = optional(string, "Premium")
    zone_redundancy_enabled = optional(bool, true)
    retention_days          = optional(number, 7)
  })
  default = {}

  validation {
    condition     = var.acr.name == null || can(regex("^[a-zA-Z0-9]{5,50}$", coalesce(var.acr.name, "xxxxx")))
    error_message = "acr.name must be 5-50 alphanumeric characters (globally unique)."
  }

  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.acr.sku)
    error_message = "acr.sku must be Basic, Standard or Premium."
  }

  validation {
    condition     = var.acr.sku == "Premium" || !var.acr.zone_redundancy_enabled
    error_message = "acr.zone_redundancy_enabled requires the Premium SKU (set it to false for Basic/Standard)."
  }

  validation {
    condition     = !var.acr.enabled || var.acr.sku == "Premium" || !var.private_endpoints.enabled
    error_message = "Private endpoints for ACR require the Premium SKU."
  }
}

###############################################################################
# Key Vault
###############################################################################

variable "key_vault" {
  description = "Key Vault (RBAC mode) for application secrets, consumed through the Secrets Store CSI driver."
  type = object({
    enabled                    = optional(bool, true)
    name                       = optional(string)
    sku_name                   = optional(string, "standard")
    soft_delete_retention_days = optional(number, 90)
    allowed_ip_ranges          = optional(list(string), [])
    admin_principal_ids        = optional(list(string), [])
  })
  default = {}

  validation {
    condition     = var.key_vault.name == null || can(regex("^[a-zA-Z][a-zA-Z0-9-]{1,22}[a-zA-Z0-9]$", coalesce(var.key_vault.name, "xxx")))
    error_message = "key_vault.name must be 3-24 characters: letters, digits and hyphens, starting with a letter."
  }

  validation {
    condition     = contains(["standard", "premium"], var.key_vault.sku_name) && var.key_vault.soft_delete_retention_days >= 7 && var.key_vault.soft_delete_retention_days <= 90
    error_message = "key_vault.sku_name must be standard or premium and soft_delete_retention_days between 7 and 90."
  }
}

###############################################################################
# Private endpoints
###############################################################################

variable "private_endpoints" {
  description = <<-EOT
    Private endpoints for ACR and Key Vault. When enabled, public network access to both is disabled.
    - `subnet_id`        subnet that hosts the endpoint NICs.
    - `create_dns_zones` create privatelink zones here and link them to `vnet_id`; set false in hub-and-spoke and pass `dns_zone_ids` (keys: "acr", "key_vault").
  EOT
  type = object({
    enabled          = bool
    subnet_id        = optional(string)
    create_dns_zones = optional(bool, true)
    vnet_id          = optional(string)
    dns_zone_ids     = optional(map(string), {})
  })
  default = {
    enabled = false
  }

  validation {
    condition     = !var.private_endpoints.enabled || var.private_endpoints.subnet_id != null
    error_message = "private_endpoints.subnet_id is required when private endpoints are enabled."
  }

  validation {
    condition     = !(var.private_endpoints.enabled && var.private_endpoints.create_dns_zones) || var.private_endpoints.vnet_id != null
    error_message = "private_endpoints.vnet_id is required to link the module-created private DNS zones."
  }

  validation {
    condition     = !(var.private_endpoints.enabled && !var.private_endpoints.create_dns_zones) || alltrue([for k in ["acr", "key_vault"] : contains(keys(var.private_endpoints.dns_zone_ids), k)])
    error_message = "private_endpoints.dns_zone_ids must contain \"acr\" and \"key_vault\" when create_dns_zones = false."
  }
}
