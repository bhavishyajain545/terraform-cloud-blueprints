# envs/aws-dev

Example root module composing [`aws-vpc`](../../modules/aws-vpc) and
[`aws-eks`](../../modules/aws-eks) into a dev environment:

- VPC `10.50.0.0/16` across three pinned AZs, **single** NAT gateway (dev cost), flow logs
- EKS with a private-only endpoint by default (`endpoint_public_access = true` + CIDRs to
  open it), deletion protection off (disposable dev cluster)
- `system` on-demand node group (2-3) and a tainted `spot` group (0-6)
- optional cluster-admin access entry for an SSO role
- provider `allowed_account_ids` guard rail and `default_tags`

```sh
cp terraform.tfvars.example terraform.tfvars   # placeholders - edit before use
terraform init -backend=false                    # or configure backend.tf first
terraform validate
terraform test                                   # mocked provider, no AWS access needed
```

`terraform plan/apply` against a real account needs credentials (SSO or OIDC role) and is
intentionally **not** part of CI.

<!-- BEGIN_TF_DOCS -->
### Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.9.0, < 2.0.0 |
| aws | ~> 6.70 |

### Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| eks | ../../modules/aws-eks | n/a |
| vpc | ../../modules/aws-vpc | n/a |

### Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| allowed\_account\_ids | AWS account IDs this configuration may run against (provider guard rail). null = no restriction. | `list(string)` | `null` | no |
| az\_suffixes | AZ letters to use in the region, e.g. ["a", "b", "c"]. Pinned explicitly so the layout never changes underneath you. | `list(string)` | <pre>[<br/>  "a",<br/>  "b",<br/>  "c"<br/>]</pre> | no |
| cluster\_admin\_role\_arn | IAM role (e.g. an SSO permission-set role) granted cluster-admin through an EKS access entry. null = none. | `string` | `null` | no |
| endpoint\_public\_access | Enable the EKS public endpoint (restricted to endpoint\_public\_access\_cidrs). false = private only, reach it via VPN / SSM. | `bool` | `false` | no |
| endpoint\_public\_access\_cidrs | CIDRs allowed to reach the public endpoint (e.g. office/VPN egress). | `list(string)` | `[]` | no |
| kubernetes\_version | EKS minor version. | `string` | `"1.35"` | no |
| name | Environment name used as prefix for every resource. | `string` | `"blueprint-dev"` | no |
| region | AWS region. | `string` | `"eu-west-1"` | no |
| vpc\_cidr | VPC CIDR. | `string` | `"10.50.0.0/16"` | no |

### Outputs

| Name | Description |
| ---- | ----------- |
| cluster\_endpoint | EKS API endpoint. |
| cluster\_name | EKS cluster name (aws eks update-kubeconfig --name ...). |
| nat\_public\_ips | Egress IPs to allow-list at third parties. |
| oidc\_provider\_arn | OIDC provider ARN for IRSA roles. |
| private\_subnet\_ids | Private subnets used by EKS. |
| vpc\_id | VPC ID. |
<!-- END_TF_DOCS -->
