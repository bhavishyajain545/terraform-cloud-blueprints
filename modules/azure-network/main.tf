locals {
  tags = merge(var.tags, { "managed-by" = "terraform", "module" = "azure-network" })

  nsg_subnets = { for k, s in var.subnets : k => s if s.create_nsg }

  # Baseline rules appended to every NSG. Azure's built-in AllowVnetInBound (65000) would
  # otherwise let anything in the VNet reach the subnet; the explicit DenyAllInbound at 4096
  # makes every subnet deny-by-default and forces callers to open what they need.
  baseline_rules = flatten([
    for k, s in local.nsg_subnets : concat(
      s.allow_azure_load_balancer_inbound ? [{
        key                          = "${k}/AllowAzureLoadBalancerInbound"
        subnet                       = k
        name                         = "AllowAzureLoadBalancerInbound"
        priority                     = 4000
        direction                    = "Inbound"
        access                       = "Allow"
        protocol                     = "*"
        source_port_range            = "*"
        destination_port_ranges      = ["*"]
        source_address_prefixes      = ["AzureLoadBalancer"]
        destination_address_prefixes = ["*"]
        description                  = "Load balancer health probes (module baseline)."
      }] : [],
      [{
        key                          = "${k}/DenyAllInbound"
        subnet                       = k
        name                         = "DenyAllInbound"
        priority                     = 4096
        direction                    = "Inbound"
        access                       = "Deny"
        protocol                     = "*"
        source_port_range            = "*"
        destination_port_ranges      = ["*"]
        source_address_prefixes      = ["*"]
        destination_address_prefixes = ["*"]
        description                  = "Deny everything not explicitly allowed (module baseline)."
      }]
    )
  ])

  custom_rules = flatten([
    for k, s in local.nsg_subnets : [
      for r in s.security_rules : merge(r, {
        key         = "${k}/${r.name}"
        subnet      = k
        description = coalesce(r.description, r.name)
      })
    ]
  ])

  all_rules = { for r in concat(local.custom_rules, local.baseline_rules) : r.key => r }
}

resource "azurerm_virtual_network" "this" {
  name                = "vnet-${var.name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = var.address_space
  dns_servers         = var.dns_servers
  tags                = local.tags
}

resource "azurerm_subnet" "this" {
  #checkov:skip=CKV2_AZURE_31:NSGs are attached via azurerm_subnet_network_security_group_association for every subnet unless explicitly opted out (create_nsg = false, e.g. GatewaySubnet); asserted in tests. Checkov loses the for_each link.
  for_each = var.subnets

  name                              = each.key
  resource_group_name               = var.resource_group_name
  virtual_network_name              = azurerm_virtual_network.this.name
  address_prefixes                  = each.value.address_prefixes
  private_endpoint_network_policies = each.value.private_endpoint_network_policies
  default_outbound_access_enabled   = var.default_outbound_access_enabled

  dynamic "service_endpoint" {
    for_each = toset(each.value.service_endpoints)
    content {
      service = service_endpoint.value
    }
  }

  dynamic "delegation" {
    for_each = each.value.delegation == null ? [] : [each.value.delegation]
    content {
      name = delegation.value.name
      service_delegation {
        name    = delegation.value.service
        actions = delegation.value.actions
      }
    }
  }
}

resource "azurerm_network_security_group" "this" {
  for_each = local.nsg_subnets

  name                = "nsg-${var.name}-${each.key}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = local.tags
}

resource "azurerm_network_security_rule" "this" {
  for_each = local.all_rules

  name                         = each.value.name
  description                  = each.value.description
  priority                     = each.value.priority
  direction                    = each.value.direction
  access                       = each.value.access
  protocol                     = each.value.protocol
  source_port_range            = each.value.source_port_range
  destination_port_range       = length(each.value.destination_port_ranges) == 1 ? each.value.destination_port_ranges[0] : null
  destination_port_ranges      = length(each.value.destination_port_ranges) > 1 ? each.value.destination_port_ranges : null
  source_address_prefix        = length(each.value.source_address_prefixes) == 1 ? each.value.source_address_prefixes[0] : null
  source_address_prefixes      = length(each.value.source_address_prefixes) > 1 ? each.value.source_address_prefixes : null
  destination_address_prefix   = length(each.value.destination_address_prefixes) == 1 ? each.value.destination_address_prefixes[0] : null
  destination_address_prefixes = length(each.value.destination_address_prefixes) > 1 ? each.value.destination_address_prefixes : null
  resource_group_name          = var.resource_group_name
  network_security_group_name  = azurerm_network_security_group.this[each.value.subnet].name
}

resource "azurerm_subnet_network_security_group_association" "this" {
  for_each = local.nsg_subnets

  subnet_id                 = azurerm_subnet.this[each.key].id
  network_security_group_id = azurerm_network_security_group.this[each.key].id
}

resource "azurerm_monitor_diagnostic_setting" "nsg" {
  for_each = var.diagnostics.enabled ? local.nsg_subnets : {}

  name                       = "diag-to-law"
  target_resource_id         = azurerm_network_security_group.this[each.key].id
  log_analytics_workspace_id = var.diagnostics.log_analytics_workspace_id

  enabled_log {
    category_group = "allLogs"
  }
}
