output "vnet_id" {
  description = "Resource ID of the virtual network."
  value       = azurerm_virtual_network.this.id
}

output "vnet_name" {
  description = "Name of the virtual network."
  value       = azurerm_virtual_network.this.name
}

output "subnet_ids" {
  description = "Map of subnet name => subnet resource ID."
  value       = { for k, s in azurerm_subnet.this : k => s.id }
}

output "subnet_address_prefixes" {
  description = "Map of subnet name => list of address prefixes."
  value       = { for k, s in azurerm_subnet.this : k => s.address_prefixes }
}

output "nsg_ids" {
  description = "Map of subnet name => ID of the NSG associated with it (only subnets with create_nsg = true)."
  value       = { for k, n in azurerm_network_security_group.this : k => n.id }
}
