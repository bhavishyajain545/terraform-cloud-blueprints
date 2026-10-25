###############################################################################
# General
###############################################################################

variable "name" {
  description = "Cluster name; also the prefix of IAM roles, KMS alias and log group."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,30}[a-z0-9]$", var.name))
    error_message = "name must be 3-32 characters of lowercase letters, digits and hyphens, starting with a letter."
  }
}

variable "tags" {
  description = "Tags applied to every resource created by this module (on top of provider default_tags)."
  type        = map(string)
  default     = {}
}

###############################################################################
# Control plane
###############################################################################

variable "kubernetes_version" {
  description = "EKS Kubernetes minor version, e.g. \"1.35\"."
  type        = string
  default     = "1.35"

  validation {
    condition     = can(regex("^1\\.[0-9]{2}$", var.kubernetes_version))
    error_message = "kubernetes_version must be a minor version such as \"1.35\"."
  }
}

variable "support_type" {
  description = "EKS version support policy. STANDARD forces upgrades at end of standard support instead of silently paying for EXTENDED support."
  type        = string
  default     = "STANDARD"

  validation {
    condition     = contains(["STANDARD", "EXTENDED"], var.support_type)
    error_message = "support_type must be STANDARD or EXTENDED."
  }
}

variable "deletion_protection" {
  description = "Block cluster deletion through the EKS API until this is turned off."
  type        = bool
  default     = true
}


variable "subnet_ids" {
  description = "Private subnet IDs (at least two AZs) for the control plane ENIs and, by default, all node groups."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "EKS needs subnets in at least two availability zones."
  }
}

variable "service_ipv4_cidr" {
  description = "Kubernetes service CIDR. Must not overlap the VPC or peered networks."
  type        = string
  default     = "172.20.0.0/16"

  validation {
    condition     = can(cidrhost(var.service_ipv4_cidr, 0)) && tonumber(split("/", var.service_ipv4_cidr)[1]) >= 12 && tonumber(split("/", var.service_ipv4_cidr)[1]) <= 24
    error_message = "service_ipv4_cidr must be a valid CIDR between /12 and /24."
  }
}

variable "endpoint_public_access" {
  description = "Expose the API server endpoint publicly (restricted by endpoint_public_access_cidrs). The private endpoint is always on."
  type        = bool
  default     = false
}

variable "endpoint_public_access_cidrs" {
  description = "CIDRs allowed to reach the public endpoint. Required (and must not be 0.0.0.0/0) when endpoint_public_access = true."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for c in var.endpoint_public_access_cidrs : can(cidrhost(c, 0)) && c != "0.0.0.0/0"])
    error_message = "endpoint_public_access_cidrs must be valid CIDRs and must not include 0.0.0.0/0."
  }

  validation {
    condition     = !var.endpoint_public_access || length(var.endpoint_public_access_cidrs) > 0
    error_message = "endpoint_public_access = true requires at least one endpoint_public_access_cidrs entry."
  }
}

variable "enabled_cluster_log_types" {
  description = "Control plane log types shipped to CloudWatch."
  type        = list(string)
  default     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  validation {
    condition     = alltrue([for t in var.enabled_cluster_log_types : contains(["api", "audit", "authenticator", "controllerManager", "scheduler"], t)])
    error_message = "enabled_cluster_log_types may only contain api, audit, authenticator, controllerManager, scheduler."
  }
}

variable "cluster_log_retention_days" {
  description = "Retention of the control plane log group."
  type        = number
  default     = 365

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.cluster_log_retention_days)
    error_message = "cluster_log_retention_days must be a value CloudWatch Logs accepts (e.g. 30, 90, 365)."
  }
}

variable "kms_key_arn" {
  description = "Existing KMS key ARN for envelope encryption of Kubernetes Secrets and the log group. null = the module creates a dedicated CMK with rotation."
  type        = string
  default     = null

  validation {
    condition     = var.kms_key_arn == null || can(regex("^arn:aws[a-z-]*:kms:", coalesce(var.kms_key_arn, "x")))
    error_message = "kms_key_arn must be a KMS key ARN."
  }
}

###############################################################################
# Access
###############################################################################

variable "access_entries" {
  description = <<-EOT
    EKS access entries (API authentication mode - no aws-auth ConfigMap). Keyed by a friendly name.
    `policy_arn` is an EKS access policy, e.g. arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy.
    `namespaces` limits the association to those namespaces; empty = cluster-wide.
  EOT
  type = map(object({
    principal_arn = string
    policy_arn    = string
    namespaces    = optional(list(string), [])
  }))
  default = {}

  validation {
    condition     = alltrue([for e in values(var.access_entries) : can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:(role|user)/", e.principal_arn)) && can(regex("^arn:aws[a-z-]*:eks::aws:cluster-access-policy/", e.policy_arn))])
    error_message = "access_entries need an IAM role/user principal_arn and an EKS cluster-access-policy policy_arn."
  }
}

###############################################################################
# Node groups
###############################################################################

variable "node_groups" {
  description = "Managed node groups keyed by name. Each gets its own hardened launch template (IMDSv2, encrypted gp3)."
  type = map(object({
    instance_types             = list(string)
    capacity_type              = optional(string, "ON_DEMAND")
    ami_type                   = optional(string, "AL2023_x86_64_STANDARD")
    min_size                   = optional(number, 1)
    max_size                   = optional(number, 3)
    desired_size               = optional(number)
    disk_size_gb               = optional(number, 50)
    max_unavailable_percentage = optional(number, 33)
    subnet_ids                 = optional(list(string))
    labels                     = optional(map(string), {})
    taints = optional(list(object({
      key    = string
      value  = optional(string)
      effect = string
    })), [])
  }))
  default = {}

  validation {
    condition     = alltrue([for k in keys(var.node_groups) : can(regex("^[a-z][a-z0-9-]{0,30}$", k))])
    error_message = "node_groups keys must be lowercase alphanumerics/hyphens, max 31 characters."
  }

  validation {
    condition = alltrue([
      for g in values(var.node_groups) :
      g.min_size >= 0 && g.min_size <= g.max_size && g.max_size >= 1 &&
      (g.desired_size == null || (coalesce(g.desired_size, 0) >= g.min_size && coalesce(g.desired_size, 0) <= g.max_size))
    ])
    error_message = "Each node group must satisfy 0 <= min_size <= desired_size <= max_size and max_size >= 1."
  }

  validation {
    condition     = alltrue([for g in values(var.node_groups) : contains(["ON_DEMAND", "SPOT"], g.capacity_type)])
    error_message = "capacity_type must be ON_DEMAND or SPOT."
  }

  validation {
    condition     = alltrue([for g in values(var.node_groups) : g.disk_size_gb >= 20 && g.max_unavailable_percentage >= 1 && g.max_unavailable_percentage <= 100])
    error_message = "disk_size_gb must be >= 20 and max_unavailable_percentage between 1 and 100."
  }

  validation {
    condition     = alltrue(flatten([for g in values(var.node_groups) : [for t in g.taints : contains(["NO_SCHEDULE", "NO_EXECUTE", "PREFER_NO_SCHEDULE"], t.effect)]]))
    error_message = "Taint effect must be NO_SCHEDULE, NO_EXECUTE or PREFER_NO_SCHEDULE."
  }
}

variable "node_ssm_access" {
  description = "Attach AmazonSSMManagedInstanceCore to nodes so they can be reached with Session Manager instead of SSH."
  type        = bool
  default     = true
}

###############################################################################
# Add-ons
###############################################################################

variable "addons" {
  description = <<-EOT
    EKS managed add-ons. `version` null = the default version for the cluster version.
    vpc-cni and aws-ebs-csi-driver automatically get an IRSA role created by this module.
    `before_compute` add-ons are installed before node groups (networking must exist before nodes join).
  EOT
  type = map(object({
    version              = optional(string)
    configuration_values = optional(string)
    before_compute       = optional(bool, false)
  }))
  default = {
    "vpc-cni"                = { before_compute = true }
    "eks-pod-identity-agent" = { before_compute = true }
    "kube-proxy"             = {}
    "coredns"                = {}
    "aws-ebs-csi-driver"     = {}
  }
}
