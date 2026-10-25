# azure-network

Virtual network, subnets and one NSG per subnet, **deny-by-default**.

## What it builds

- `azurerm_virtual_network` with optional custom DNS servers.
- One `azurerm_subnet` per entry in `subnets` (service endpoints, delegation and
  private-endpoint network policies per subnet). Implicit *default outbound access* is
  disabled, so egress has to be explicit (NAT gateway, firewall, LB).
- One NSG per subnet (opt out with `create_nsg = false`, e.g. for `GatewaySubnet`), with two
  baseline rules appended by the module:

  | Priority | Rule | Why |
  |----------|------|-----|
  | 4000 | `AllowAzureLoadBalancerInbound` (toggle) | keeps LB health probes working |
  | 4096 | `DenyAllInbound` | overrides Azure's built-in `AllowVnetInBound` (65000), so nothing reaches a subnet unless a caller rule allows it |

  Caller rules must use priorities 100-3999. Validation rejects inbound *Allow* rules from
  `Internet`/`*`/`0.0.0.0/0` to 22, 3389 or all ports.
- Optional NSG diagnostic settings to Log Analytics (`diagnostics.enabled`).

## Usage

```hcl
module "network" {
  source = "../../modules/azure-network"

  name                = "app-dev"
  location            = "westeurope"
  resource_group_name = azurerm_resource_group.this.name
  address_space       = ["10.40.0.0/16"]

  subnets = {
    aks-nodes = {
      address_prefixes = ["10.40.0.0/22"]
      security_rules = [{
        name                         = "AllowVnetInbound"
        priority                     = 100
        direction                    = "Inbound"
        access                       = "Allow"
        protocol                     = "*"
        destination_port_ranges      = ["*"]
        source_address_prefixes      = ["VirtualNetwork"]
        destination_address_prefixes = ["VirtualNetwork"]
      }]
    }
    private-endpoints = {
      address_prefixes                  = ["10.40.8.0/24"]
      private_endpoint_network_policies = "NetworkSecurityGroupEnabled"
    }
  }

  diagnostics = {
    enabled                    = true
    log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id
  }
}
```

## Tests

`tests/azure_network.tftest.hcl` (mocked `azurerm`, no credentials): NSG per subnet and
opt-out, deny-all at 4096 on every NSG, LB-probe toggle, default outbound disabled, tags,
diagnostics toggle, and rejection of Internet-to-SSH rules / reserved priorities.

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
| [azurerm_monitor_diagnostic_setting.nsg](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_diagnostic_setting) | resource |
| [azurerm_network_security_group.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/network_security_group) | resource |
| [azurerm_network_security_rule.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/network_security_rule) | resource |
| [azurerm_subnet.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet) | resource |
| [azurerm_subnet_network_security_group_association.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet_network_security_group_association) | resource |
| [azurerm_virtual_network.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/virtual_network) | resource |

### Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| address\_space | Address space(s) of the virtual network in CIDR notation. | `list(string)` | n/a | yes |
| location | Azure region for all resources, e.g. "westeurope". | `string` | n/a | yes |
| name | Base name used for the virtual network and derived resource names (lowercase letters, digits and hyphens). | `string` | n/a | yes |
| resource\_group\_name | Name of an existing resource group to deploy into. | `string` | n/a | yes |
| subnets | Subnets to create, keyed by subnet name. Every subnet gets its own NSG unless `create_nsg = false`<br/>(required for some delegated/special subnets such as GatewaySubnet).<br/><br/>- `address_prefixes`                  CIDRs of the subnet (must sit inside `address_space`).<br/>- `service_endpoints`                 e.g. ["Microsoft.KeyVault"].<br/>- `private_endpoint_network_policies` "Disabled" \| "Enabled" \| "NetworkSecurityGroupEnabled" \| "RouteTableEnabled".<br/>- `delegation`                        optional service delegation.<br/>- `create_nsg`                        create and associate a dedicated NSG (default true).<br/>- `allow_azure_load_balancer_inbound` keep LB health probes working under the deny-all rule (default true).<br/>- `security_rules`                    extra NSG rules; priorities 100-3999 (4000-4096 are reserved by this module). | <pre>map(object({<br/>    address_prefixes                  = list(string)<br/>    service_endpoints                 = optional(list(string), [])<br/>    private_endpoint_network_policies = optional(string, "Enabled")<br/>    delegation = optional(object({<br/>      name    = string<br/>      service = string<br/>      actions = optional(list(string), [])<br/>    }))<br/>    create_nsg                        = optional(bool, true)<br/>    allow_azure_load_balancer_inbound = optional(bool, true)<br/>    security_rules = optional(list(object({<br/>      name                         = string<br/>      priority                     = number<br/>      direction                    = string<br/>      access                       = string<br/>      protocol                     = string<br/>      source_port_range            = optional(string, "*")<br/>      destination_port_ranges      = list(string)<br/>      source_address_prefixes      = list(string)<br/>      destination_address_prefixes = list(string)<br/>      description                  = optional(string)<br/>    })), [])<br/>  }))</pre> | n/a | yes |
| default\_outbound\_access\_enabled | Allow implicit default outbound internet access for VMs in the subnets. Disabled by default; use a NAT gateway, firewall or load balancer for explicit egress. | `bool` | `false` | no |
| diagnostics | Send NSG diagnostic logs to a Log Analytics workspace. `enabled` must be known at plan time, so it is a separate flag from the workspace ID. | <pre>object({<br/>    enabled                    = bool<br/>    log_analytics_workspace_id = optional(string)<br/>  })</pre> | <pre>{<br/>  "enabled": false<br/>}</pre> | no |
| dns\_servers | Custom DNS servers for the VNet. Empty list uses Azure-provided DNS. | `list(string)` | `[]` | no |
| tags | Tags applied to every resource created by this module. | `map(string)` | `{}` | no |

### Outputs

| Name | Description |
| ---- | ----------- |
| nsg\_ids | Map of subnet name => ID of the NSG associated with it (only subnets with create\_nsg = true). |
| subnet\_address\_prefixes | Map of subnet name => list of address prefixes. |
| subnet\_ids | Map of subnet name => subnet resource ID. |
| vnet\_id | Resource ID of the virtual network. |
| vnet\_name | Name of the virtual network. |
<!-- END_TF_DOCS -->
