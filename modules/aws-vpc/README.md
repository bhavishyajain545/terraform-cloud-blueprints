# aws-vpc

Multi-AZ VPC with public and private subnets, NAT per AZ / single NAT / no NAT, an S3
gateway endpoint and KMS-encrypted flow logs.

## What it builds

- VPC with DNS support/hostnames; the **default security group is adopted and emptied** so
  nothing can accidentally rely on it.
- One public and one private subnet per AZ in `azs`. Default carve-up for a /16: public /24s
  at the bottom of the range, private /20s above them (room for VPC CNI pod IPs). Explicit
  CIDR lists are accepted. Public subnets do **not** auto-assign public IPs.
- Subnets carry `kubernetes.io/role/elb` / `internal-elb` tags for the AWS Load Balancer
  Controller; extra tags per tier via `public_subnet_tags` / `private_subnet_tags`.
- `nat_gateway_mode`:

  | Mode | NAT gateways | When |
  |------|--------------|------|
  | `per_az` (default) | one per AZ, each private route table uses its own AZ's NAT | production - an AZ outage doesn't take egress down elsewhere |
  | `single` | one, shared by all private route tables | dev / cost-sensitive |
  | `none` | none, no default route in private subnets | fully private workloads using VPC endpoints |

  There is always one private route table per AZ, so switching modes only changes routes.
- S3 gateway endpoint on the private route tables (free; keeps ECR layer pulls off the NAT).
- Flow logs (ALL traffic, 60 s aggregation) to a CloudWatch log group with 365-day retention,
  encrypted by a dedicated CMK with rotation. The IAM role's trust policy is scoped with
  `aws:SourceAccount` against confused-deputy use.

## Usage

```hcl
module "vpc" {
  source = "../../modules/aws-vpc"

  name             = "app-dev"
  cidr_block       = "10.50.0.0/16"
  azs              = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]
  nat_gateway_mode = "single"

  private_subnet_tags = {
    "kubernetes.io/cluster/app-dev" = "shared"
  }
}
```

## Tests

`tests/aws_vpc.tftest.hcl` (mocked `aws`): subnet layout/CIDRs/AZ order, discovery tags,
NAT count and routing for `per_az` / `single` / `none`, flow logs on + encrypted + 1 year,
KMS and trust policies (decoded JSON), default SG empty, explicit CIDRs, tags, input validation.

```sh
terraform init -backend=false && terraform test
```

<!-- BEGIN_TF_DOCS -->
### Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.9.0, < 2.0.0 |
| aws | ~> 6.70 |

### Providers

| Name | Version |
| ---- | ------- |
| aws | ~> 6.70 |

### Resources

| Name | Type |
| ---- | ---- |
| [aws_cloudwatch_log_group.flow_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_default_security_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/default_security_group) | resource |
| [aws_eip.nat](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eip) | resource |
| [aws_flow_log.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/flow_log) | resource |
| [aws_iam_role.flow_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.flow_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_internet_gateway.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/internet_gateway) | resource |
| [aws_kms_alias.flow_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_alias) | resource |
| [aws_kms_key.flow_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key) | resource |
| [aws_nat_gateway.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/nat_gateway) | resource |
| [aws_route.private_nat](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_route.public_internet](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_route_table.private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table) | resource |
| [aws_route_table.public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table) | resource |
| [aws_route_table_association.private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association) | resource |
| [aws_route_table_association.public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association) | resource |
| [aws_subnet.private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet) | resource |
| [aws_subnet.public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet) | resource |
| [aws_vpc.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc) | resource |
| [aws_vpc_endpoint.s3](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_endpoint) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

### Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| azs | Availability zones to spread subnets across (2-6). One public and one private subnet is created per AZ. | `list(string)` | n/a | yes |
| cidr\_block | IPv4 CIDR of the VPC. /16 to /20; a /16 is recommended so private subnets have room for pod IPs (VPC CNI). | `string` | n/a | yes |
| name | Name prefix for the VPC and every resource in it. | `string` | n/a | yes |
| enable\_s3\_gateway\_endpoint | Add a (free) S3 gateway endpoint to the private route tables so S3/ECR layer traffic skips the NAT. | `bool` | `true` | no |
| flow\_logs | VPC flow logs to CloudWatch Logs, encrypted with a module-managed KMS key. | <pre>object({<br/>    enabled                  = optional(bool, true)<br/>    traffic_type             = optional(string, "ALL")<br/>    retention_days           = optional(number, 365)<br/>    max_aggregation_interval = optional(number, 60)<br/>  })</pre> | `{}` | no |
| nat\_gateway\_mode | Egress for private subnets: "per\_az" (one NAT per AZ, no cross-AZ dependency - production), "single" (one shared NAT - cheaper, dev) or "none" (fully private, use VPC endpoints). | `string` | `"per_az"` | no |
| private\_subnet\_cidrs | Explicit private subnet CIDRs (one per AZ). Empty = carve large (/4-bit) blocks after the public range. | `list(string)` | `[]` | no |
| private\_subnet\_tags | Extra tags for private subnets (e.g. karpenter.sh/discovery). kubernetes.io/role/internal-elb = 1 is always added. | `map(string)` | `{}` | no |
| public\_subnet\_cidrs | Explicit public subnet CIDRs (one per AZ). Empty = carve /8-bit-larger blocks from the start of the VPC range. | `list(string)` | `[]` | no |
| public\_subnet\_tags | Extra tags for public subnets. kubernetes.io/role/elb = 1 is always added for AWS Load Balancer Controller discovery. | `map(string)` | `{}` | no |
| tags | Tags applied to every resource created by this module (on top of provider default\_tags). | `map(string)` | `{}` | no |

### Outputs

| Name | Description |
| ---- | ----------- |
| azs | Availability zones used, in subnet order. |
| flow\_log\_group\_name | CloudWatch log group receiving VPC flow logs (null if disabled). |
| nat\_gateway\_ids | NAT gateway IDs (empty when nat\_gateway\_mode = none). |
| nat\_public\_ips | Egress public IPs of the NAT gateways - allow-list these at third parties. |
| private\_route\_table\_ids | Private route table IDs (one per AZ), e.g. for additional gateway endpoints. |
| private\_subnet\_cidrs | CIDRs of the private subnets. |
| private\_subnet\_ids | Private subnet IDs, one per AZ (same order as azs). Use these for EKS nodes and the control plane ENIs. |
| public\_subnet\_cidrs | CIDRs of the public subnets. |
| public\_subnet\_ids | Public subnet IDs, one per AZ (same order as azs). |
| vpc\_cidr\_block | IPv4 CIDR of the VPC. |
| vpc\_id | ID of the VPC. |
<!-- END_TF_DOCS -->
