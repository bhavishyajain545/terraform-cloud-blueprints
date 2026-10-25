variable "name" {
  description = "Base name used for the virtual network and derived resource names (lowercase letters, digits and hyphens)."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,38}[a-z0-9]$", var.name))
    error_message = "name must be 3-40 characters of lowercase letters, digits and hyphens, and must not start or end with a hyphen."
  }
}

variable "location" {
  description = "Azure region for all resources, e.g. \"westeurope\"."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]+$", var.location))
    error_message = "location must be a normalised Azure region name such as \"westeurope\" (lowercase, no spaces)."
  }
}

variable "resource_group_name" {
  description = "Name of an existing resource group to deploy into."
  type        = string
}

variable "address_space" {
  description = "Address space(s) of the virtual network in CIDR notation."
  type        = list(string)

  validation {
    condition     = length(var.address_space) > 0 && alltrue([for c in var.address_space : can(cidrhost(c, 0))])
    error_message = "address_space must contain at least one valid IPv4 CIDR block."
  }
}

variable "dns_servers" {
  description = "Custom DNS servers for the VNet. Empty list uses Azure-provided DNS."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for ip in var.dns_servers : can(cidrhost("${ip}/32", 0))])
    error_message = "dns_servers must contain valid IPv4 addresses."
  }
}

variable "subnets" {
  description = <<-EOT
    Subnets to create, keyed by subnet name. Every subnet gets its own NSG unless `create_nsg = false`
    (required for some delegated/special subnets such as GatewaySubnet).

    - `address_prefixes`                  CIDRs of the subnet (must sit inside `address_space`).
    - `service_endpoints`                 e.g. ["Microsoft.KeyVault"].
    - `private_endpoint_network_policies` "Disabled" | "Enabled" | "NetworkSecurityGroupEnabled" | "RouteTableEnabled".
    - `delegation`                        optional service delegation.
    - `create_nsg`                        create and associate a dedicated NSG (default true).
    - `allow_azure_load_balancer_inbound` keep LB health probes working under the deny-all rule (default true).
    - `security_rules`                    extra NSG rules; priorities 100-3999 (4000-4096 are reserved by this module).
  EOT
  type = map(object({
    address_prefixes                  = list(string)
    service_endpoints                 = optional(list(string), [])
    private_endpoint_network_policies = optional(string, "Enabled")
    delegation = optional(object({
      name    = string
      service = string
      actions = optional(list(string), [])
    }))
    create_nsg                        = optional(bool, true)
    allow_azure_load_balancer_inbound = optional(bool, true)
    security_rules = optional(list(object({
      name                         = string
      priority                     = number
      direction                    = string
      access                       = string
      protocol                     = string
      source_port_range            = optional(string, "*")
      destination_port_ranges      = list(string)
      source_address_prefixes      = list(string)
      destination_address_prefixes = list(string)
      description                  = optional(string)
    })), [])
  }))

  validation {
    condition     = length(var.subnets) > 0
    error_message = "At least one subnet must be defined."
  }

  validation {
    condition = alltrue(flatten([
      for s in values(var.subnets) : [for p in s.address_prefixes : can(cidrhost(p, 0))]
    ]))
    error_message = "Every subnet address prefix must be a valid CIDR block."
  }

  validation {
    condition = alltrue([
      for s in values(var.subnets) :
      contains(["Disabled", "Enabled", "NetworkSecurityGroupEnabled", "RouteTableEnabled"], s.private_endpoint_network_policies)
    ])
    error_message = "private_endpoint_network_policies must be one of Disabled, Enabled, NetworkSecurityGroupEnabled, RouteTableEnabled."
  }

  validation {
    condition = alltrue(flatten([
      for s in values(var.subnets) : [
        for r in s.security_rules :
        r.priority >= 100 && r.priority <= 3999 &&
        contains(["Inbound", "Outbound"], r.direction) &&
        contains(["Allow", "Deny"], r.access) &&
        contains(["Tcp", "Udp", "Icmp", "Esp", "Ah", "*"], r.protocol)
      ]
    ]))
    error_message = "security_rules: priority must be 100-3999 (4000+ is reserved for module baseline rules), direction Inbound|Outbound, access Allow|Deny, protocol Tcp|Udp|Icmp|Esp|Ah|*."
  }

  validation {
    condition = alltrue(flatten([
      for s in values(var.subnets) : [
        for r in s.security_rules :
        !(r.direction == "Inbound" && r.access == "Allow" && anytrue([for p in r.source_address_prefixes : contains(["*", "0.0.0.0/0", "Internet", "Any"], p)]) && anytrue([for port in r.destination_port_ranges : contains(["22", "3389", "*"], port)]))
      ]
    ]))
    error_message = "Inbound Allow rules from the Internet to SSH (22), RDP (3389) or all ports are not permitted. Use Azure Bastion or a private jump host."
  }
}

variable "default_outbound_access_enabled" {
  description = "Allow implicit default outbound internet access for VMs in the subnets. Disabled by default; use a NAT gateway, firewall or load balancer for explicit egress."
  type        = bool
  default     = false
}

variable "diagnostics" {
  description = "Send NSG diagnostic logs to a Log Analytics workspace. `enabled` must be known at plan time, so it is a separate flag from the workspace ID."
  type = object({
    enabled                    = bool
    log_analytics_workspace_id = optional(string)
  })
  default = {
    enabled = false
  }

  validation {
    condition     = !var.diagnostics.enabled || var.diagnostics.log_analytics_workspace_id != null
    error_message = "diagnostics.log_analytics_workspace_id is required when diagnostics.enabled is true."
  }
}

variable "tags" {
  description = "Tags applied to every resource created by this module."
  type        = map(string)
  default     = {}
}
