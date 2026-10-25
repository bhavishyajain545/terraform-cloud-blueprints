locals {
  tags = merge({
    environment = "dev"
    project     = "terraform-cloud-blueprints"
    cost-center = "platform"
  }, var.tags)

  pod_cidr     = "10.244.0.0/16"
  service_cidr = "172.16.0.0/16"

  aks_subnet = cidrsubnet(var.address_space, 6, 0) # /22 - node IPs only (overlay)
  pe_subnet  = cidrsubnet(var.address_space, 8, 8) # /24 - private endpoints
}

resource "azurerm_resource_group" "this" {
  name     = "rg-${var.name}"
  location = var.location
  tags     = local.tags
}

# One workspace for the environment: AKS (Container Insights + resource logs), ACR, Key Vault and NSGs.
resource "azurerm_log_analytics_workspace" "this" {
  name                         = "law-${var.name}"
  location                     = azurerm_resource_group.this.location
  resource_group_name          = azurerm_resource_group.this.name
  sku                          = "PerGB2018"
  retention_in_days            = 30
  local_authentication_enabled = false
  tags                         = local.tags
}

module "network" {
  source = "../../modules/azure-network"

  name                = var.name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  address_space       = [var.address_space]
  tags                = local.tags

  subnets = {
    aks-nodes = {
      address_prefixes = [local.aks_subnet]
      security_rules = [
        {
          name                         = "AllowVnetInbound"
          priority                     = 100
          direction                    = "Inbound"
          access                       = "Allow"
          protocol                     = "*"
          destination_port_ranges      = ["*"]
          source_address_prefixes      = ["VirtualNetwork"]
          destination_address_prefixes = ["VirtualNetwork"]
          description                  = "Node-to-node and API server VNet traffic."
        },
        {
          name                         = "AllowPodCidrInbound"
          priority                     = 110
          direction                    = "Inbound"
          access                       = "Allow"
          protocol                     = "*"
          destination_port_ranges      = ["*"]
          source_address_prefixes      = [local.pod_cidr]
          destination_address_prefixes = ["*"]
          description                  = "Azure CNI Overlay pod-to-pod traffic across nodes."
        },
      ]
    }
    private-endpoints = {
      address_prefixes                  = [local.pe_subnet]
      private_endpoint_network_policies = "NetworkSecurityGroupEnabled"
      allow_azure_load_balancer_inbound = false
      security_rules = [{
        name                         = "AllowHttpsFromAks"
        priority                     = 100
        direction                    = "Inbound"
        access                       = "Allow"
        protocol                     = "Tcp"
        destination_port_ranges      = ["443"]
        source_address_prefixes      = [local.aks_subnet]
        destination_address_prefixes = [local.pe_subnet]
        description                  = "Nodes reach ACR and Key Vault private endpoints."
      }]
    }
  }

  diagnostics = {
    enabled                    = true
    log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id
  }
}

module "aks" {
  source = "../../modules/azure-aks"

  name                = var.name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  kubernetes_version  = var.kubernetes_version
  tags                = local.tags

  # Dev: no uptime SLA, small system pool. Everything security-related stays on.
  #checkov:skip=CKV_AZURE_170:Dev environment runs the Free control-plane tier on purpose (no SLA needed); the module default is Standard.
  sku_tier               = "Free"
  admin_group_object_ids = var.admin_group_object_ids

  vnet_subnet_id = module.network.subnet_ids["aks-nodes"]
  pod_cidr       = local.pod_cidr
  service_cidr   = local.service_cidr

  # Pool settings are spelled out (rather than relying on module defaults) so the
  # intent is visible in review and static scanners can evaluate them.
  system_node_pool = {
    vm_size      = "Standard_D4ds_v5"
    min_count    = 1
    max_count    = 3
    max_pods     = 110
    os_disk_type = "Ephemeral"
  }

  user_node_pools = {
    apps = {
      vm_size      = "Standard_D4ds_v5"
      min_count    = 0
      max_count    = 5
      max_pods     = 110
      os_disk_type = "Ephemeral"
      node_labels = {
        "workload" = "apps"
      }
    }
  }

  host_encryption_enabled = true

  create_log_analytics_workspace = false
  log_analytics_workspace_id     = azurerm_log_analytics_workspace.this.id

  acr = {
    name                    = var.acr_name
    sku                     = "Premium"
    zone_redundancy_enabled = true
  }

  key_vault = {
    name = var.key_vault_name
  }

  private_endpoints = {
    enabled   = true
    subnet_id = module.network.subnet_ids["private-endpoints"]
    vnet_id   = module.network.vnet_id
  }
}
