variable "name" {
  description = "Name prefix for the VPC and every resource in it."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,38}[a-z0-9]$", var.name))
    error_message = "name must be 3-40 characters of lowercase letters, digits and hyphens."
  }
}

variable "cidr_block" {
  description = "IPv4 CIDR of the VPC. /16 to /20; a /16 is recommended so private subnets have room for pod IPs (VPC CNI)."
  type        = string

  validation {
    condition     = can(cidrhost(var.cidr_block, 0)) && tonumber(split("/", var.cidr_block)[1]) >= 16 && tonumber(split("/", var.cidr_block)[1]) <= 20
    error_message = "cidr_block must be a valid IPv4 CIDR between /16 and /20."
  }
}

variable "azs" {
  description = "Availability zones to spread subnets across (2-6). One public and one private subnet is created per AZ."
  type        = list(string)

  validation {
    condition     = length(var.azs) >= 2 && length(var.azs) <= 6 && length(distinct(var.azs)) == length(var.azs)
    error_message = "azs must contain 2-6 distinct availability zones."
  }
}

variable "public_subnet_cidrs" {
  description = "Explicit public subnet CIDRs (one per AZ). Empty = carve /8-bit-larger blocks from the start of the VPC range."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for c in var.public_subnet_cidrs : can(cidrhost(c, 0))])
    error_message = "public_subnet_cidrs must be valid CIDR blocks."
  }

  validation {
    condition     = length(var.public_subnet_cidrs) == 0 || length(var.public_subnet_cidrs) == length(var.azs)
    error_message = "public_subnet_cidrs must be empty or have one entry per AZ."
  }
}

variable "private_subnet_cidrs" {
  description = "Explicit private subnet CIDRs (one per AZ). Empty = carve large (/4-bit) blocks after the public range."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for c in var.private_subnet_cidrs : can(cidrhost(c, 0))])
    error_message = "private_subnet_cidrs must be valid CIDR blocks."
  }

  validation {
    condition     = length(var.private_subnet_cidrs) == 0 || length(var.private_subnet_cidrs) == length(var.azs)
    error_message = "private_subnet_cidrs must be empty or have one entry per AZ."
  }
}

variable "nat_gateway_mode" {
  description = "Egress for private subnets: \"per_az\" (one NAT per AZ, no cross-AZ dependency - production), \"single\" (one shared NAT - cheaper, dev) or \"none\" (fully private, use VPC endpoints)."
  type        = string
  default     = "per_az"

  validation {
    condition     = contains(["per_az", "single", "none"], var.nat_gateway_mode)
    error_message = "nat_gateway_mode must be per_az, single or none."
  }
}

variable "enable_s3_gateway_endpoint" {
  description = "Add a (free) S3 gateway endpoint to the private route tables so S3/ECR layer traffic skips the NAT."
  type        = bool
  default     = true
}

variable "flow_logs" {
  description = "VPC flow logs to CloudWatch Logs, encrypted with a module-managed KMS key."
  type = object({
    enabled                  = optional(bool, true)
    traffic_type             = optional(string, "ALL")
    retention_days           = optional(number, 365)
    max_aggregation_interval = optional(number, 60)
  })
  default = {}

  validation {
    condition     = contains(["ACCEPT", "REJECT", "ALL"], var.flow_logs.traffic_type)
    error_message = "flow_logs.traffic_type must be ACCEPT, REJECT or ALL."
  }

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.flow_logs.retention_days)
    error_message = "flow_logs.retention_days must be a value CloudWatch Logs accepts (e.g. 30, 90, 365)."
  }

  validation {
    condition     = contains([60, 600], var.flow_logs.max_aggregation_interval)
    error_message = "flow_logs.max_aggregation_interval must be 60 or 600."
  }
}

variable "public_subnet_tags" {
  description = "Extra tags for public subnets. kubernetes.io/role/elb = 1 is always added for AWS Load Balancer Controller discovery."
  type        = map(string)
  default     = {}
}

variable "private_subnet_tags" {
  description = "Extra tags for private subnets (e.g. karpenter.sh/discovery). kubernetes.io/role/internal-elb = 1 is always added."
  type        = map(string)
  default     = {}
}

variable "tags" {
  description = "Tags applied to every resource created by this module (on top of provider default_tags)."
  type        = map(string)
  default     = {}
}
