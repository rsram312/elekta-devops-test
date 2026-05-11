# Elekta DevOps Test - Azure Infrastructure Deployment Pipeline

End-to-end Infrastructure-as-Code solution: Terraform provisioning Azure infrastructure plus an Azure DevOps multi-stage CI/CD pipeline that validates, plans, and applies changes with a production approval gate.

## What gets deployed

| Resource | Detail |
| --- | --- |
| Resource Group | `elekta-devops-test` (West US) |
| Virtual Network | `vnet-elekta-devops-test` (`10.0.0.0/16`) |
| Subnet | `snet-vms` (`10.0.1.0/24`) |
| Network Security Group | Allows RDP from a single admin IP and intra-subnet RDP |
| Public IPs | `pip-vm-test-1`, `pip-vm-test-2` (Standard SKU, Static) |
| Network Interfaces | `nic-vm-test-1`, `nic-vm-test-2` |
| Virtual Machines | `vm-test-1`, `vm-test-2` - Windows Server 2022 Datacenter Azure Edition, `Standard_D2s_v3` |

Outputs (required per the assessment):

- `resource_group_name`
- `virtual_machine_names`
- `public_ip_addresses` (map: VM name -> public IP)
- `private_ip_addresses` (map: VM name -> private IP)

## Repository layout

```
.
├── .gitignore
├── README.md                       <- this file
├── azure-pipelines.yml             <- Azure DevOps multi-stage pipeline
├── docs/
│   ├── pipeline.md                 <- detailed pipeline walkthrough
│   └── design-decisions.md         <- assumptions and trade-offs
└── terraform/
    ├── .terraform.lock.hcl         <- provider version lock (committed)
    ├── compute.tf                  <- NICs and VMs
    ├── main.tf                     <- resource group, locals
    ├── network.tf                  <- VNet, subnet, NSG, public IPs
    ├── outputs.tf                  <- required outputs
    ├── providers.tf                <- provider + remote state backend
    ├── terraform.tfvars            <- gitignored, holds admin_password
    ├── terraform.tfvars.example    <- copy to terraform.tfvars and fill in
    └── variables.tf
```

## Prerequisites

- Terraform `>= 1.6` (tested with 1.9.x)
- Azure CLI (`az`)
- An Azure subscription (Pay-As-You-Go; Free Trial subscriptions cannot deploy modern VM SKUs)
- An Azure Storage Account for remote Terraform state (one-time bootstrap, see below)
- For CI/CD: an Azure DevOps organization and project with a Microsoft-hosted parallel job available

## One-time setup

### Bootstrap the remote Terraform state backend

Run once per Azure subscription, signed in as a user with Contributor+ on the subscription:

```bash
az login

LOCATION="westus"
STATE_RG="rg-tfstate"
STATE_SA="elektatfstate"            # change if not globally unique
STATE_CONTAINER="tfstate"

az group create --name "$STATE_RG" --location "$LOCATION"

az storage account create \
  --name "$STATE_SA" \
  --resource-group "$STATE_RG" \
  --location "$LOCATION" \
  --sku Standard_LRS \
  --kind StorageV2 \
  --min-tls-version TLS1_2 \
  --allow-blob-public-access false \
  --https-only true

az storage account blob-service-properties update \
  --account-name "$STATE_SA" \
  --resource-group "$STATE_RG" \
  --enable-versioning true \
  --enable-delete-retention true \
  --delete-retention-days 30

az storage container create \
  --name "$STATE_CONTAINER" \
  --account-name "$STATE_SA" \
  --auth-mode login
```

Grant your user `Storage Blob Data Contributor` on the storage account so Terraform can access state via AAD auth:

```bash
USER_OBJECT_ID=$(az ad signed-in-user show --query id -o tsv)
SA_ID=$(az storage account show -g "$STATE_RG" -n "$STATE_SA" --query id -o tsv)

az role assignment create \
  --assignee-object-id "$USER_OBJECT_ID" \
  --assignee-principal-type User \
  --role "Storage Blob Data Contributor" \
  --scope "$SA_ID"
```

If your storage account name differs from `elektatfstate`, update `terraform/providers.tf` accordingly.

## Deployment

There are two paths: **local** (for development) and **pipeline-driven** (for promoted changes).

### Local deployment

```bash
cd terraform

cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars: set admin_password to "ElektaDevopsTest123!"
# Set admin_source_ip to your public IP (curl ifconfig.me) if different.

terraform init
terraform plan
terraform apply
```

Apply takes ~5 minutes on first run (Windows VMs are the slow part). Subsequent runs against unchanged infrastructure complete in seconds.

### Pipeline-driven deployment

Pushes to `main` trigger the Azure DevOps pipeline (`azure-pipelines.yml`). The pipeline runs:

1. **Validate** - `terraform fmt -check`, `terraform init`, `terraform validate`
2. **Plan** - `terraform plan`, saves the plan as a pipeline artifact
3. **Apply** - downloads the saved plan and applies it. Gated by a manual approval check on the `prod` Azure DevOps Environment.

See [`docs/pipeline.md`](docs/pipeline.md) for the full walkthrough, including the one-time Azure DevOps setup (service connections, environments, variable groups).

## Outputs

After apply, locally or via pipeline:

```bash
terraform output
```

Produces:

- `resource_group_name` - name of the resource group
- `virtual_machine_names` - list of VM names
- `public_ip_addresses` - map of VM name to public IP
- `private_ip_addresses` - map of VM name to private IP

The pipeline also publishes `tf-outputs.json` as a pipeline artifact after each successful apply.

## Connect

RDP to either VM's public IP using:
- Username: `Elekta`
- Password: `ElektaDevopsTest123!`

From inside one VM you can RDP to the other over its private IP (`10.0.1.4` or `10.0.1.5`). Verified end-to-end during development.

## Cleanup

```bash
cd terraform
terraform destroy
```

The remote state backend storage account (`rg-tfstate` / `elektatfstate`) is intentionally left intact. Destroy it manually with `az group delete --name rg-tfstate --yes` if no longer needed.

## Security notes

- The admin password is never committed - it lives only in `terraform.tfvars` (gitignored), as the `TF_VAR_admin_password` environment variable locally, or as a secret variable group `elekta-devops-secrets` in Azure DevOps.
- Terraform state is stored in Azure Blob Storage with TLS 1.2 minimum, public blob access disabled, AAD-only authentication, blob versioning enabled, and 30-day soft delete.
- The pipeline authenticates to Azure via Workload Identity Federation (OIDC) - no client secrets are stored anywhere.
- The NSG allows RDP only from a single configurable admin IP plus intra-subnet traffic. The default `admin_source_ip` is a placeholder; override via `terraform.tfvars` for any real deployment.
- For production, public RDP would be replaced with Azure Bastion; public IPs on VMs are kept here per the assessment requirement.

## Documentation

- [`docs/pipeline.md`](docs/pipeline.md) - pipeline stage-by-stage walkthrough, Azure DevOps setup, troubleshooting
- [`docs/design-decisions.md`](docs/design-decisions.md) - assumptions, trade-offs, and what we'd do differently in a real environment