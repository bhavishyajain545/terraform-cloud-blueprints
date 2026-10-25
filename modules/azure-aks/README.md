# azure-aks

Private-by-default AKS cluster with its supporting services: ACR, Key Vault (RBAC),
private endpoints, Log Analytics and diagnostic settings.

## What it builds

| Area | Resources / settings |
|------|----------------------|
| Control plane | `azurerm_kubernetes_cluster`: private API server (`System` / BYO private DNS zone / public with authorized ranges), Standard tier, `patch` upgrade channel + `NodeImage` OS channel inside a weekly maintenance window, local accounts disabled, Entra ID + Azure RBAC for Kubernetes |
| Identity | user-assigned control-plane and kubelet identities (stable across cluster rebuilds) with *Network Contributor* on the node subnet and *Managed Identity Operator* on the kubelet identity; OIDC issuer + Workload ID |
| Networking | Azure CNI **Overlay** + **Cilium** data plane/network policy by default; classic Azure CNI with a pod subnet supported; `loadBalancer` / UDR / NAT gateway egress |
| Node pools | system pool (`only_critical_addons_enabled`, autoscaled `min_count`-`max_count`, AzureLinux, ephemeral OS disk, zones 1-3) + any number of autoscaled user pools, incl. Spot (scale from zero, correct taint, no surge) |
| Add-ons | Azure Policy (toggle), Defender for Containers (toggle), Secrets Store CSI driver with rotation, Image Cleaner, Container Insights with MSI auth |
| ACR | Premium, admin user and anonymous pull off, zone redundant, retention policy, dedicated data endpoints, *AcrPull* for the kubelet identity |
| Key Vault | RBAC authorization, purge protection, default-deny firewall, *Key Vault Secrets User* for the CSI driver identity, optional admins |
| Private endpoints | ACR + Key Vault endpoints; creates `privatelink.*` zones and VNet links, or uses hub zones you pass in. Public access on both is switched off when enabled |
| Observability | module-created or central Log Analytics workspace; diagnostic settings for AKS (`kube-audit-admin`, `guard`, autoscaler, ...), ACR and Key Vault |

Toggles that cost money or need subscription preparation are explicit: `defender_enabled`
(billed per vCore) defaults to `false`; `host_encryption_enabled` defaults to `true` and
needs the `Microsoft.Compute/EncryptionAtHost` feature registered once per subscription.

## Usage

```hcl
module "aks" {
  source = "../../modules/azure-aks"

  name                = "app-dev"
  location            = "westeurope"
  resource_group_name = azurerm_resource_group.this.name
  vnet_subnet_id      = module.network.subnet_ids["aks-nodes"]

  admin_group_object_ids = ["<entra-group-object-id>"]

  system_node_pool = { min_count = 2, max_count = 5 }
  user_node_pools = {
    apps  = { vm_size = "Standard_D4ds_v5", min_count = 1, max_count = 10 }
    batch = { vm_size = "Standard_D8ds_v5", max_count = 20, priority = "Spot" }
  }

  acr       = { name = "acrappdev001" }
  key_vault = { name = "kv-app-dev-001" }

  private_endpoints = {
    enabled   = true
    subnet_id = module.network.subnet_ids["private-endpoints"]
    vnet_id   = module.network.vnet_id
  }
}
```

## Tests

`tests/azure_aks.tftest.hcl` (mocked `azurerm`): private cluster by default, public cluster
requires (non-0.0.0.0/0) authorized ranges, autoscaling bounds for system and user pools,
inverted bounds rejected, Spot handling, overlay/Cilium vs classic CNI, Azure Policy and
Defender toggles, ACR hardening + AcrPull, Key Vault RBAC/purge protection/firewall,
private endpoints (module DNS and hub DNS), diagnostics, BYO workspace, tags.

```sh
terraform init -backend=false && terraform test
```

<!-- BEGIN_TF_DOCS -->
### Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.9.0, < 2.0.0 |
| azurerm | ~> 5.11 |

### Providers

| Name | Version |
| ---- | ------- |
| azurerm | ~> 5.11 |

### Resources

| Name | Type |
| ---- | ---- |
| [azurerm_container_registry.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/container_registry) | resource |
| [azurerm_key_vault.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/key_vault) | resource |
| [azurerm_kubernetes_cluster.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/kubernetes_cluster) | resource |
| [azurerm_kubernetes_cluster_node_pool.user](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/kubernetes_cluster_node_pool) | resource |
| [azurerm_log_analytics_workspace.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/log_analytics_workspace) | resource |
| [azurerm_monitor_diagnostic_setting.acr](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_diagnostic_setting) | resource |
| [azurerm_monitor_diagnostic_setting.aks](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_diagnostic_setting) | resource |
| [azurerm_monitor_diagnostic_setting.kv](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_diagnostic_setting) | resource |
| [azurerm_private_dns_zone.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_dns_zone) | resource |
| [azurerm_private_dns_zone_virtual_network_link.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_dns_zone_virtual_network_link) | resource |
| [azurerm_private_endpoint.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_endpoint) | resource |
| [azurerm_role_assignment.control_plane_kubelet_operator](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_assignment.control_plane_network](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_assignment.control_plane_private_dns](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_assignment.kubelet_acr_pull](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_assignment.kv_admins](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_assignment.kv_secrets_provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_user_assigned_identity.control_plane](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/user_assigned_identity) | resource |
| [azurerm_user_assigned_identity.kubelet](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/user_assigned_identity) | resource |
| [azurerm_client_config.current](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/client_config) | data source |

### Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| location | Azure region, e.g. "westeurope". | `string` | n/a | yes |
| name | Cluster name (also used to derive names of the ACR, Key Vault, identities and workspace). | `string` | n/a | yes |
| resource\_group\_name | Existing resource group for the cluster and its supporting resources. | `string` | n/a | yes |
| vnet\_subnet\_id | Subnet ID for the node pools (and the API server VNet integration, if used). | `string` | n/a | yes |
| acr | Azure Container Registry created for the cluster. The kubelet identity gets AcrPull. Premium is required for private endpoints and retention policy. | <pre>object({<br/>    enabled                 = optional(bool, true)<br/>    name                    = optional(string)<br/>    sku                     = optional(string, "Premium")<br/>    zone_redundancy_enabled = optional(bool, true)<br/>    retention_days          = optional(number, 7)<br/>  })</pre> | `{}` | no |
| admin\_group\_object\_ids | Entra ID group object IDs granted cluster-admin through Azure RBAC for Kubernetes. | `list(string)` | `[]` | no |
| api\_server\_authorized\_ip\_ranges | CIDRs allowed to reach a *public* API server. Ignored for private clusters. Must be non-empty for public clusters. | `list(string)` | `[]` | no |
| auto\_scaler\_profile | Cluster autoscaler tuning shared by all pools. | <pre>object({<br/>    expander                         = optional(string, "least-waste")<br/>    balance_similar_node_groups      = optional(bool, true)<br/>    scale_down_unneeded              = optional(string, "10m")<br/>    scale_down_utilization_threshold = optional(string, "0.5")<br/>    max_unready_percentage           = optional(number, 45)<br/>  })</pre> | `{}` | no |
| automatic\_upgrade\_channel | Cluster auto-upgrade channel. | `string` | `"patch"` | no |
| azure\_policy\_enabled | Install the Azure Policy add-on (Gatekeeper) so policy assignments are enforced in-cluster. | `bool` | `true` | no |
| cluster\_log\_categories | AKS resource log categories sent to Log Analytics. kube-audit-admin is audit without the noisy get/list events. | `list(string)` | <pre>[<br/>  "kube-apiserver",<br/>  "kube-audit-admin",<br/>  "kube-controller-manager",<br/>  "kube-scheduler",<br/>  "cluster-autoscaler",<br/>  "guard"<br/>]</pre> | no |
| create\_log\_analytics\_workspace | Create a Log Analytics workspace. Set false and pass log\_analytics\_workspace\_id to use a central one. | `bool` | `true` | no |
| defender\_enabled | Enable Microsoft Defender for Containers sensor (billed per vCore). | `bool` | `false` | no |
| disk\_encryption\_set\_id | Disk Encryption Set for customer-managed-key encryption of node OS/data disks. null = platform-managed keys. | `string` | `null` | no |
| host\_encryption\_enabled | Encrypt node temp disks, caches and OS/data disk flows at the VM host. Requires the Microsoft.Compute/EncryptionAtHost feature to be registered on the subscription once. | `bool` | `true` | no |
| image\_cleaner\_interval\_hours | Interval for the Image Cleaner (Eraser) that removes unused, vulnerable images from nodes. | `number` | `48` | no |
| key\_vault | Key Vault (RBAC mode) for application secrets, consumed through the Secrets Store CSI driver. | <pre>object({<br/>    enabled                    = optional(bool, true)<br/>    name                       = optional(string)<br/>    sku_name                   = optional(string, "standard")<br/>    soft_delete_retention_days = optional(number, 90)<br/>    allowed_ip_ranges          = optional(list(string), [])<br/>    admin_principal_ids        = optional(list(string), [])<br/>  })</pre> | `{}` | no |
| kubernetes\_version | Kubernetes minor version (e.g. "1.34"). null lets AKS pick the default; patch upgrades follow automatic\_upgrade\_channel. | `string` | `null` | no |
| log\_analytics\_workspace\_id | Existing Log Analytics workspace ID (required when create\_log\_analytics\_workspace = false). | `string` | `null` | no |
| log\_retention\_days | Retention of the module-created Log Analytics workspace. | `number` | `30` | no |
| maintenance\_window | Weekly window (UTC) used for both cluster and node OS auto-upgrades. | <pre>object({<br/>    day_of_week    = optional(string, "Sunday")<br/>    start_time     = optional(string, "02:00")<br/>    duration_hours = optional(number, 4)<br/>  })</pre> | `{}` | no |
| network\_data\_plane | Data plane: "cilium" (eBPF, Cilium network policy) or "azure". | `string` | `"cilium"` | no |
| network\_plugin\_mode | "overlay" (Azure CNI Overlay: pods get IPs from pod\_cidr, saves VNet space) or null for classic Azure CNI (pods get VNet IPs). | `string` | `"overlay"` | no |
| network\_policy | Network policy engine. Must be "cilium" when network\_data\_plane is cilium. | `string` | `"cilium"` | no |
| node\_os\_upgrade\_channel | Node OS image upgrade channel. | `string` | `"NodeImage"` | no |
| outbound\_type | Egress path for nodes. Use userDefinedRouting behind an Azure Firewall/NVA in hub-and-spoke. | `string` | `"loadBalancer"` | no |
| pod\_cidr | Pod CIDR for Azure CNI Overlay. Must not overlap the VNet or service\_cidr. | `string` | `"10.244.0.0/16"` | no |
| pod\_subnet\_id | Dedicated pod subnet for classic Azure CNI with dynamic IP allocation. Only used when network\_plugin\_mode is null. | `string` | `null` | no |
| private\_cluster\_enabled | Expose the API server only on a private endpoint inside the VNet. | `bool` | `true` | no |
| private\_dns\_zone\_id | Private DNS zone for the private API server: "System" (AKS-managed), "None", or the ID of a zone you own (hub-and-spoke). | `string` | `"System"` | no |
| private\_endpoints | Private endpoints for ACR and Key Vault. When enabled, public network access to both is disabled.<br/>- `subnet_id`        subnet that hosts the endpoint NICs.<br/>- `create_dns_zones` create privatelink zones here and link them to `vnet_id`; set false in hub-and-spoke and pass `dns_zone_ids` (keys: "acr", "key\_vault"). | <pre>object({<br/>    enabled          = bool<br/>    subnet_id        = optional(string)<br/>    create_dns_zones = optional(bool, true)<br/>    vnet_id          = optional(string)<br/>    dns_zone_ids     = optional(map(string), {})<br/>  })</pre> | <pre>{<br/>  "enabled": false<br/>}</pre> | no |
| run\_command\_enabled | Allow `az aks command invoke`. Handy for private clusters without a jump host, but it is an extra control-plane entry point. | `bool` | `false` | no |
| service\_cidr | Kubernetes service CIDR. Must not overlap the VNet or pod\_cidr. | `string` | `"172.16.0.0/16"` | no |
| sku\_tier | AKS control plane tier. Standard gives the uptime SLA; Free is only for throw-away clusters. | `string` | `"Standard"` | no |
| system\_node\_pool | System node pool (critical add-ons only). Autoscaled between min\_count and max\_count. | <pre>object({<br/>    name            = optional(string, "system")<br/>    vm_size         = optional(string, "Standard_D4ds_v5")<br/>    min_count       = optional(number, 2)<br/>    max_count       = optional(number, 5)<br/>    max_pods        = optional(number, 110)<br/>    os_sku          = optional(string, "AzureLinux")<br/>    os_disk_type    = optional(string, "Ephemeral")<br/>    os_disk_size_gb = optional(number, 128)<br/>    zones           = optional(list(string), ["1", "2", "3"])<br/>    max_surge       = optional(string, "33%")<br/>  })</pre> | `{}` | no |
| tags | Tags applied to every resource created by this module. | `map(string)` | `{}` | no |
| user\_node\_pools | Additional user node pools keyed by pool name (1-12 lowercase alphanumerics). Each is autoscaled between min\_count and max\_count. | <pre>map(object({<br/>    vm_size         = string<br/>    min_count       = optional(number, 0)<br/>    max_count       = number<br/>    max_pods        = optional(number, 110)<br/>    os_sku          = optional(string, "AzureLinux")<br/>    os_disk_type    = optional(string, "Ephemeral")<br/>    os_disk_size_gb = optional(number, 128)<br/>    zones           = optional(list(string), ["1", "2", "3"])<br/>    priority        = optional(string, "Regular")<br/>    spot_max_price  = optional(number, -1)<br/>    node_labels     = optional(map(string), {})<br/>    node_taints     = optional(list(string), [])<br/>    max_surge       = optional(string, "33%")<br/>  }))</pre> | `{}` | no |
| workload\_identity\_enabled | Enable Entra Workload ID (also enables the OIDC issuer). Pods federate to managed identities instead of using secrets. | `bool` | `true` | no |

### Outputs

| Name | Description |
| ---- | ----------- |
| acr\_id | Resource ID of the container registry (null if disabled). |
| acr\_login\_server | Login server of the container registry (null if disabled). |
| api\_server\_fqdn | API server FQDN: the private FQDN for private clusters, otherwise the public one. |
| cluster\_id | Resource ID of the AKS cluster. |
| cluster\_name | Name of the AKS cluster. |
| control\_plane\_identity\_id | Resource ID of the control plane user-assigned identity. |
| key\_vault\_id | Resource ID of the Key Vault (null if disabled). |
| key\_vault\_uri | Vault URI for SDKs and the Secrets Store CSI SecretProviderClass (null if disabled). |
| kubelet\_identity | User-assigned identity used by the kubelet (image pulls). |
| log\_analytics\_workspace\_id | Log Analytics workspace receiving Container Insights and diagnostic logs. |
| node\_resource\_group | Resource group AKS uses for node VMSS, load balancers and disks. |
| oidc\_issuer\_url | OIDC issuer URL, used as the issuer of federated identity credentials for Workload ID. |
| secrets\_provider\_identity\_client\_id | Client ID of the Secrets Store CSI driver identity, for SecretProviderClass userAssignedIdentityID. |
| user\_node\_pool\_ids | Map of user node pool name => resource ID. |
<!-- END_TF_DOCS -->
