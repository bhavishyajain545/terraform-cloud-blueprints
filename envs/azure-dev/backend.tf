# Remote state - example only. Uncomment and fill in to use an Azure Storage backend.
#
# Recommended setup for the state account (created once, out of band or by a bootstrap stack):
#   - StorageV2, GRS/GZRS, blob versioning + soft delete on, public network access disabled
#     (or restricted to CI runners), shared-key access disabled.
#   - The CI identity gets "Storage Blob Data Contributor" on the container only.
#   - Blob leases provide state locking natively; no extra lock table is needed.
#
# terraform {
#   backend "azurerm" {
#     resource_group_name  = "rg-tfstate"
#     storage_account_name = "sttfstateexample001"
#     container_name       = "tfstate"
#     key                  = "azure-dev/platform.tfstate"
#     use_azuread_auth     = true # Entra ID auth instead of storage account keys
#     # use_oidc           = true # GitHub Actions OIDC federation, no client secret
#   }
# }
