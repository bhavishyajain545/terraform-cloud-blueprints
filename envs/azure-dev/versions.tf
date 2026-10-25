terraform {
  required_version = ">= 1.9.0, < 2.0.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.11"
    }
  }
}

provider "azurerm" {
  # Credentials come from the environment (az login, OIDC federation in CI, or ARM_* variables).
  # Nothing secret is configured here.
  subscription_id     = var.subscription_id
  storage_use_azuread = true

  features {
    key_vault {
      # Purge protection is on; never purge on destroy.
      purge_soft_delete_on_destroy = false
    }
    resource_group {
      prevent_deletion_if_contains_resources = true
    }
  }
}
