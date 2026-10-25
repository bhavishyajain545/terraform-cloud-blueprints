variable "region" {
  description = "AWS region."
  type        = string
  default     = "eu-west-1"
}

variable "allowed_account_ids" {
  description = "AWS account IDs this configuration may run against (provider guard rail). null = no restriction."
  type        = list(string)
  default     = null
}

variable "name" {
  description = "Environment name used as prefix for every resource."
  type        = string
  default     = "blueprint-dev"
}

variable "vpc_cidr" {
  description = "VPC CIDR."
  type        = string
  default     = "10.50.0.0/16"
}

variable "az_suffixes" {
  description = "AZ letters to use in the region, e.g. [\"a\", \"b\", \"c\"]. Pinned explicitly so the layout never changes underneath you."
  type        = list(string)
  default     = ["a", "b", "c"]

  validation {
    condition     = alltrue([for s in var.az_suffixes : can(regex("^[a-z]$", s))])
    error_message = "az_suffixes must be single lowercase letters."
  }
}

variable "kubernetes_version" {
  description = "EKS minor version."
  type        = string
  default     = "1.35"
}

variable "endpoint_public_access" {
  description = "Enable the EKS public endpoint (restricted to endpoint_public_access_cidrs). false = private only, reach it via VPN / SSM."
  type        = bool
  default     = false
}

variable "endpoint_public_access_cidrs" {
  description = "CIDRs allowed to reach the public endpoint (e.g. office/VPN egress)."
  type        = list(string)
  default     = []
}

variable "cluster_admin_role_arn" {
  description = "IAM role (e.g. an SSO permission-set role) granted cluster-admin through an EKS access entry. null = none."
  type        = string
  default     = null
}
