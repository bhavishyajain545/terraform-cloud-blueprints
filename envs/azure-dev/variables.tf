variable "subscription_id" {
  description = "Target Azure subscription ID. Can also be supplied via ARM_SUBSCRIPTION_ID."
  type        = string
  default     = null
}

variable "location" {
  description = "Azure region."
  type        = string
  default     = "westeurope"
}

variable "name" {
  description = "Workload/environment name used in every resource name."
  type        = string
  default     = "blueprint-dev"
}

variable "address_space" {
  description = "VNet address space. Pod and service CIDRs (overlay) live outside it."
  type        = string
  default     = "10.40.0.0/16"
}

variable "kubernetes_version" {
  description = "AKS minor version. null = AKS default."
  type        = string
  default     = null
}

variable "admin_group_object_ids" {
  description = "Entra ID groups that get cluster-admin via Azure RBAC."
  type        = list(string)
  default     = []
}

variable "acr_name" {
  description = "Globally unique ACR name (5-50 alphanumerics)."
  type        = string
  default     = "acrblueprintdev001"
}

variable "key_vault_name" {
  description = "Globally unique Key Vault name (3-24 chars)."
  type        = string
  default     = "kv-blueprint-dev-001"
}

variable "tags" {
  description = "Extra tags merged into the environment defaults."
  type        = map(string)
  default     = {}
}
