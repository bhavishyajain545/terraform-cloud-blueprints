# Composition test: the whole azure-dev stack plans and "applies" against a mocked provider.
# Proves the modules wire together (subnet IDs, workspace, private endpoints) at zero cost.
# The azurerm provider still parses resource IDs passed between resources, so mocked
# resources return well-formed IDs.

mock_provider "azurerm" {
  mock_data "azurerm_client_config" {
    defaults = {
      tenant_id = "00000000-0000-0000-0000-000000000001"
    }
  }

  mock_resource "azurerm_log_analytics_workspace" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-blueprint-dev/providers/Microsoft.OperationalInsights/workspaces/law-blueprint-dev"
    }
  }
  mock_resource "azurerm_virtual_network" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-blueprint-dev/providers/Microsoft.Network/virtualNetworks/vnet-blueprint-dev"
    }
  }
  mock_resource "azurerm_subnet" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-blueprint-dev/providers/Microsoft.Network/virtualNetworks/vnet-blueprint-dev/subnets/mocked"
    }
  }
  mock_resource "azurerm_network_security_group" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-blueprint-dev/providers/Microsoft.Network/networkSecurityGroups/nsg-mocked"
    }
  }
  mock_resource "azurerm_user_assigned_identity" {
    defaults = {
      id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-blueprint-dev/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-mocked"
      principal_id = "00000000-0000-0000-0000-0000000000aa"
      client_id    = "00000000-0000-0000-0000-0000000000bb"
    }
  }
  mock_resource "azurerm_kubernetes_cluster" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-blueprint-dev/providers/Microsoft.ContainerService/managedClusters/aks-blueprint-dev"
      key_vault_secrets_provider = {
        secret_identity = [{
          client_id                 = "00000000-0000-0000-0000-0000000000cc"
          object_id                 = "00000000-0000-0000-0000-0000000000dd"
          user_assigned_identity_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-blueprint-dev-nodes/providers/Microsoft.ManagedIdentity/userAssignedIdentities/azurekeyvaultsecretsprovider"
        }]
      }
    }
  }
  mock_resource "azurerm_container_registry" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-blueprint-dev/providers/Microsoft.ContainerRegistry/registries/acrblueprintdev001"
    }
  }
  mock_resource "azurerm_key_vault" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-blueprint-dev/providers/Microsoft.KeyVault/vaults/kv-blueprint-dev-001"
    }
  }
  mock_resource "azurerm_private_dns_zone" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-blueprint-dev/providers/Microsoft.Network/privateDnsZones/privatelink.example"
    }
  }
}

variables {
  subscription_id = "00000000-0000-0000-0000-000000000000"
}

run "stack_plans" {
  command = plan

  assert {
    condition     = module.aks.cluster_name == "aks-blueprint-dev"
    error_message = "Unexpected cluster name."
  }

  assert {
    condition     = toset(keys(module.network.nsg_ids)) == toset(["aks-nodes", "private-endpoints"])
    error_message = "Both subnets must be NSG-protected."
  }
}

run "stack_applies_with_mocks" {
  command = apply

  assert {
    condition     = module.aks.log_analytics_workspace_id == azurerm_log_analytics_workspace.this.id
    error_message = "AKS must report to the environment workspace."
  }

  assert {
    condition     = length(module.network.subnet_ids) == 2 && module.aks.secrets_provider_identity_client_id == "00000000-0000-0000-0000-0000000000cc"
    error_message = "Stack outputs not wired through."
  }
}
