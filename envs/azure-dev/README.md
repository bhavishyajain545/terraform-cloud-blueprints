# envs/azure-dev

Example root module composing [`azure-network`](../../modules/azure-network) and
[`azure-aks`](../../modules/azure-aks) into a dev environment:

- resource group + one Log Analytics workspace shared by AKS, ACR, Key Vault and the NSGs
- VNet `10.40.0.0/16` with `aks-nodes` (/22, node IPs only - pods use the overlay
  `10.244.0.0/16`) and `private-endpoints` (/24), both deny-by-default
- private AKS (Free tier for dev, everything security-related still on), autoscaled system
  pool 1-3 and an `apps` user pool 0-5
- ACR + Key Vault reachable only through private endpoints

```sh
cp terraform.tfvars.example terraform.tfvars   # placeholders - edit before use
terraform init -backend=false                    # or configure backend.tf first
terraform validate
terraform test                                   # mocked provider, no Azure access needed
```

`terraform plan/apply` against a real subscription needs credentials (`az login` or OIDC)
and is intentionally **not** part of CI.

<!-- BEGIN_TF_DOCS -->
### Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.9.0, < 2.0.0 |
| azurerm | ~> 5.11 |

### Providers

| Name | Version |
| ---- | ------- |
| azurerm | ~> 5.11 |

### Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| aks | ../../modules/azure-aks | n/a |
| network | ../../modules/azure-network | n/a |

### Resources

| Name | Type |
| ---- | ---- |
| [azurerm_log_analytics_workspace.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/log_analytics_workspace) | resource |
| [azurerm_resource_group.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/resource_group) | resource |

### Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| acr\_name | Globally unique ACR name (5-50 alphanumerics). | `string` | `"acrblueprintdev001"` | no |
| address\_space | VNet address space. Pod and service CIDRs (overlay) live outside it. | `string` | `"10.40.0.0/16"` | no |
| admin\_group\_object\_ids | Entra ID groups that get cluster-admin via Azure RBAC. | `list(string)` | `[]` | no |
| key\_vault\_name | Globally unique Key Vault name (3-24 chars). | `string` | `"kv-blueprint-dev-001"` | no |
| kubernetes\_version | AKS minor version. null = AKS default. | `string` | `null` | no |
| location | Azure region. | `string` | `"westeurope"` | no |
| name | Workload/environment name used in every resource name. | `string` | `"blueprint-dev"` | no |
| subscription\_id | Target Azure subscription ID. Can also be supplied via ARM\_SUBSCRIPTION\_ID. | `string` | `null` | no |
| tags | Extra tags merged into the environment defaults. | `map(string)` | `{}` | no |

### Outputs

| Name | Description |
| ---- | ----------- |
| acr\_login\_server | Registry login server. |
| api\_server\_fqdn | Private API server FQDN. |
| cluster\_name | AKS cluster name (az aks get-credentials --name ...). |
| key\_vault\_uri | Key Vault URI. |
| oidc\_issuer\_url | Issuer for Workload ID federated credentials. |
| resource\_group\_name | Resource group holding the environment. |
| subnet\_ids | Subnets created for the environment. |
<!-- END_TF_DOCS -->
