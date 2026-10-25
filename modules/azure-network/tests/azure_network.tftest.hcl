# Unit tests for modules/azure-network.
# mock_provider means no Azure API is ever called: zero credentials, zero cost.

mock_provider "azurerm" {}

variables {
  name                = "unit"
  location            = "westeurope"
  resource_group_name = "rg-unit"
  address_space       = ["10.10.0.0/16"]
  tags = {
    environment = "test"
    owner       = "platform"
  }
  subnets = {
    workload = {
      address_prefixes = ["10.10.0.0/22"]
      security_rules = [{
        name                         = "AllowHttpsFromVnet"
        priority                     = 200
        direction                    = "Inbound"
        access                       = "Allow"
        protocol                     = "Tcp"
        destination_port_ranges      = ["443"]
        source_address_prefixes      = ["VirtualNetwork"]
        destination_address_prefixes = ["10.10.0.0/22"]
      }]
    }
    endpoints = {
      address_prefixes                  = ["10.10.8.0/24"]
      private_endpoint_network_policies = "NetworkSecurityGroupEnabled"
      allow_azure_load_balancer_inbound = false
    }
    GatewaySubnet = {
      address_prefixes = ["10.10.255.0/27"]
      create_nsg       = false
    }
  }
}

run "nsg_per_subnet_except_opted_out" {
  command = plan

  assert {
    condition     = length(azurerm_network_security_group.this) == 2
    error_message = "Expected one NSG per subnet with create_nsg = true (2)."
  }

  assert {
    condition     = !contains(keys(azurerm_network_security_group.this), "GatewaySubnet")
    error_message = "GatewaySubnet opted out and must not get an NSG."
  }

  assert {
    condition     = length(azurerm_subnet_network_security_group_association.this) == 2
    error_message = "Every NSG must be associated with its subnet."
  }
}

run "deny_by_default_on_every_nsg" {
  command = plan

  assert {
    condition = alltrue([
      for k in keys(azurerm_network_security_group.this) :
      azurerm_network_security_rule.this["${k}/DenyAllInbound"].access == "Deny" &&
      azurerm_network_security_rule.this["${k}/DenyAllInbound"].priority == 4096 &&
      azurerm_network_security_rule.this["${k}/DenyAllInbound"].direction == "Inbound" &&
      azurerm_network_security_rule.this["${k}/DenyAllInbound"].source_address_prefix == "*"
    ])
    error_message = "Every NSG must carry a DenyAllInbound rule at priority 4096."
  }

  assert {
    condition     = azurerm_network_security_rule.this["workload/AllowAzureLoadBalancerInbound"].source_address_prefix == "AzureLoadBalancer"
    error_message = "LB health-probe allow rule missing on the workload subnet."
  }

  assert {
    condition     = !contains(keys(azurerm_network_security_rule.this), "endpoints/AllowAzureLoadBalancerInbound")
    error_message = "LB allow rule must be omitted when allow_azure_load_balancer_inbound = false."
  }

  assert {
    condition     = azurerm_network_security_rule.this["workload/AllowHttpsFromVnet"].destination_port_range == "443"
    error_message = "Custom rule was not rendered."
  }
}

run "secure_subnet_defaults" {
  command = plan

  assert {
    condition     = alltrue([for s in azurerm_subnet.this : s.default_outbound_access_enabled == false])
    error_message = "Implicit default outbound access must be disabled on every subnet."
  }

  assert {
    condition     = azurerm_subnet.this["endpoints"].private_endpoint_network_policies == "NetworkSecurityGroupEnabled"
    error_message = "private_endpoint_network_policies not passed through."
  }

  assert {
    condition     = length(azurerm_monitor_diagnostic_setting.nsg) == 0
    error_message = "Diagnostics must be off unless explicitly enabled."
  }
}

run "tags_applied" {
  command = plan

  assert {
    condition     = azurerm_virtual_network.this.tags["environment"] == "test" && azurerm_virtual_network.this.tags["managed-by"] == "terraform"
    error_message = "Caller tags and module tags must both be applied to the VNet."
  }

  assert {
    condition     = alltrue([for n in azurerm_network_security_group.this : n.tags["owner"] == "platform"])
    error_message = "Tags must be applied to every NSG."
  }
}

run "diagnostics_enabled_creates_one_setting_per_nsg" {
  command = plan

  variables {
    diagnostics = {
      enabled                    = true
      log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-unit/providers/Microsoft.OperationalInsights/workspaces/law-unit"
    }
  }

  assert {
    condition     = length(azurerm_monitor_diagnostic_setting.nsg) == 2
    error_message = "Expected one diagnostic setting per NSG."
  }
}

run "rejects_ssh_from_internet" {
  command = plan

  variables {
    subnets = {
      bad = {
        address_prefixes = ["10.10.0.0/24"]
        security_rules = [{
          name                         = "OpenSsh"
          priority                     = 100
          direction                    = "Inbound"
          access                       = "Allow"
          protocol                     = "Tcp"
          destination_port_ranges      = ["22"]
          source_address_prefixes      = ["Internet"]
          destination_address_prefixes = ["*"]
        }]
      }
    }
  }

  expect_failures = [var.subnets]
}

run "rejects_reserved_priority" {
  command = plan

  variables {
    subnets = {
      bad = {
        address_prefixes = ["10.10.0.0/24"]
        security_rules = [{
          name                         = "TooLate"
          priority                     = 4050
          direction                    = "Inbound"
          access                       = "Allow"
          protocol                     = "Tcp"
          destination_port_ranges      = ["443"]
          source_address_prefixes      = ["VirtualNetwork"]
          destination_address_prefixes = ["*"]
        }]
      }
    }
  }

  expect_failures = [var.subnets]
}

run "diagnostics_require_workspace" {
  command = plan

  variables {
    diagnostics = { enabled = true }
  }

  expect_failures = [var.diagnostics]
}
