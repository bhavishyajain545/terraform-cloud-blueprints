# aws-eks

EKS cluster with managed node groups, IRSA, KMS envelope encryption of Secrets, a
private-only API endpoint by default and the core managed add-ons.

## What it builds

| Area | Resources / settings |
|------|----------------------|
| Encryption | dedicated CMK (rotation, 30-day deletion window) for Kubernetes Secrets envelope encryption and the control plane log group - or bring your own `kms_key_arn` |
| Control plane | private endpoint always on; public endpoint off unless `endpoint_public_access = true` **and** CIDRs are given (0.0.0.0/0 rejected); all five log types to CloudWatch (365 days, KMS); `STANDARD` support policy so you are not silently billed for extended support; deletion protection |
| Access | `authentication_mode = "API"` (access entries, no `aws-auth` ConfigMap), no implicit cluster-creator admin; `access_entries` map with cluster- or namespace-scoped EKS access policies |
| IRSA | IAM OIDC provider for the cluster issuer; IRSA roles for `vpc-cni` and `aws-ebs-csi-driver` with trust pinned to the exact service account **and** audience |
| Nodes | managed node groups (on-demand or Spot, labels, taints, auto-repair, rolling updates by percentage) on a per-group launch template: **IMDSv2 required, hop limit 1** (pods can't steal the node role), encrypted gp3 root volume, detailed monitoring. Node role: worker + ECR pull-only + optional SSM; the CNI policy sits on the IRSA role instead |
| Add-ons | `vpc-cni` and `eks-pod-identity-agent` before nodes; `kube-proxy`, `coredns`, `aws-ebs-csi-driver` after; versions pinnable per add-on |

## Usage

```hcl
module "eks" {
  source = "../../modules/aws-eks"

  name               = "app-dev"
  kubernetes_version = "1.35"
  subnet_ids         = module.vpc.private_subnet_ids

  access_entries = {
    platform-admins = {
      principal_arn = "arn:aws:iam::111122223333:role/platform-admins"
      policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
    }
  }

  node_groups = {
    system = { instance_types = ["m7i.large"], min_size = 2, max_size = 4 }
    spot = {
      instance_types = ["m7i.xlarge", "m6i.xlarge"]
      capacity_type  = "SPOT"
      min_size       = 0
      max_size       = 10
      taints         = [{ key = "capacity", value = "spot", effect = "NO_SCHEDULE" }]
    }
  }
}
```

## Tests

`tests/aws_eks.tftest.hcl` (mocked `aws`): Secrets encryption with the CMK, scoped cluster
KMS policy, private endpoint by default, public endpoint requires restricted CIDRs, log
types/retention/encryption, node group bounds and Spot, IMDSv2 + encrypted gp3 launch
templates, OIDC provider and IRSA trust conditions, add-on ordering and IRSA wiring, CNI
policy fallback, BYO KMS, namespaced access entries, validation, tags.

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
| [aws_cloudwatch_log_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_eks_access_entry.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_access_entry) | resource |
| [aws_eks_access_policy_association.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_access_policy_association) | resource |
| [aws_eks_addon.before_compute](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_addon) | resource |
| [aws_eks_addon.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_addon) | resource |
| [aws_eks_cluster.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_cluster) | resource |
| [aws_eks_node_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_node_group) | resource |
| [aws_iam_openid_connect_provider.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_openid_connect_provider) | resource |
| [aws_iam_role.cluster](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.irsa](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.node](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.cluster_kms](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy_attachment.cluster](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.irsa](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.node](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_kms_alias.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_alias) | resource |
| [aws_kms_key.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key) | resource |
| [aws_launch_template.node](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/launch_template) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

### Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| name | Cluster name; also the prefix of IAM roles, KMS alias and log group. | `string` | n/a | yes |
| subnet\_ids | Private subnet IDs (at least two AZs) for the control plane ENIs and, by default, all node groups. | `list(string)` | n/a | yes |
| access\_entries | EKS access entries (API authentication mode - no aws-auth ConfigMap). Keyed by a friendly name.<br/>`policy_arn` is an EKS access policy, e.g. arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy.<br/>`namespaces` limits the association to those namespaces; empty = cluster-wide. | <pre>map(object({<br/>    principal_arn = string<br/>    policy_arn    = string<br/>    namespaces    = optional(list(string), [])<br/>  }))</pre> | `{}` | no |
| addons | EKS managed add-ons. `version` null = the default version for the cluster version.<br/>vpc-cni and aws-ebs-csi-driver automatically get an IRSA role created by this module.<br/>`before_compute` add-ons are installed before node groups (networking must exist before nodes join). | <pre>map(object({<br/>    version              = optional(string)<br/>    configuration_values = optional(string)<br/>    before_compute       = optional(bool, false)<br/>  }))</pre> | <pre>{<br/>  "aws-ebs-csi-driver": {},<br/>  "coredns": {},<br/>  "eks-pod-identity-agent": {<br/>    "before_compute": true<br/>  },<br/>  "kube-proxy": {},<br/>  "vpc-cni": {<br/>    "before_compute": true<br/>  }<br/>}</pre> | no |
| cluster\_log\_retention\_days | Retention of the control plane log group. | `number` | `365` | no |
| deletion\_protection | Block cluster deletion through the EKS API until this is turned off. | `bool` | `true` | no |
| enabled\_cluster\_log\_types | Control plane log types shipped to CloudWatch. | `list(string)` | <pre>[<br/>  "api",<br/>  "audit",<br/>  "authenticator",<br/>  "controllerManager",<br/>  "scheduler"<br/>]</pre> | no |
| endpoint\_public\_access | Expose the API server endpoint publicly (restricted by endpoint\_public\_access\_cidrs). The private endpoint is always on. | `bool` | `false` | no |
| endpoint\_public\_access\_cidrs | CIDRs allowed to reach the public endpoint. Required (and must not be 0.0.0.0/0) when endpoint\_public\_access = true. | `list(string)` | `[]` | no |
| kms\_key\_arn | Existing KMS key ARN for envelope encryption of Kubernetes Secrets and the log group. null = the module creates a dedicated CMK with rotation. | `string` | `null` | no |
| kubernetes\_version | EKS Kubernetes minor version, e.g. "1.35". | `string` | `"1.35"` | no |
| node\_groups | Managed node groups keyed by name. Each gets its own hardened launch template (IMDSv2, encrypted gp3). | <pre>map(object({<br/>    instance_types             = list(string)<br/>    capacity_type              = optional(string, "ON_DEMAND")<br/>    ami_type                   = optional(string, "AL2023_x86_64_STANDARD")<br/>    min_size                   = optional(number, 1)<br/>    max_size                   = optional(number, 3)<br/>    desired_size               = optional(number)<br/>    disk_size_gb               = optional(number, 50)<br/>    max_unavailable_percentage = optional(number, 33)<br/>    subnet_ids                 = optional(list(string))<br/>    labels                     = optional(map(string), {})<br/>    taints = optional(list(object({<br/>      key    = string<br/>      value  = optional(string)<br/>      effect = string<br/>    })), [])<br/>  }))</pre> | `{}` | no |
| node\_ssm\_access | Attach AmazonSSMManagedInstanceCore to nodes so they can be reached with Session Manager instead of SSH. | `bool` | `true` | no |
| service\_ipv4\_cidr | Kubernetes service CIDR. Must not overlap the VPC or peered networks. | `string` | `"172.20.0.0/16"` | no |
| support\_type | EKS version support policy. STANDARD forces upgrades at end of standard support instead of silently paying for EXTENDED support. | `string` | `"STANDARD"` | no |
| tags | Tags applied to every resource created by this module (on top of provider default\_tags). | `map(string)` | `{}` | no |

### Outputs

| Name | Description |
| ---- | ----------- |
| cluster\_arn | ARN of the EKS cluster. |
| cluster\_certificate\_authority\_data | Base64 CA bundle of the API server (for kubeconfig / the kubernetes provider). |
| cluster\_endpoint | API server endpoint. |
| cluster\_name | Name of the EKS cluster. |
| cluster\_security\_group\_id | EKS-managed cluster security group (attached to control plane ENIs and managed nodes). |
| irsa\_role\_arns | Map of add-on name => IRSA role ARN created by this module. |
| kms\_key\_arn | KMS key used for Secrets envelope encryption and control plane logs. |
| log\_group\_name | CloudWatch log group for control plane logs. |
| node\_group\_arns | Map of node group name => ARN. |
| node\_role\_arn | IAM role ARN used by managed node groups. |
| oidc\_issuer\_url | OIDC issuer URL of the cluster. |
| oidc\_provider\_arn | IAM OIDC provider ARN - use as the Federated principal in IRSA trust policies. |
<!-- END_TF_DOCS -->
