# Elekta DevOps Test - Azure Infrastructure

Terraform configuration that provisions an Azure resource group, virtual network, network security group, and two Windows Server 2022 VMs reachable via RDP.

> **Status:** Terraform code complete and verified end-to-end (deploy + RDP). CI/CD pipeline pending.

## What gets deployed

- **Resource Group** `elekta-devops-test` (West US)
- **Virtual Network** `vnet-elekta-devops-test` (`10.0.0.0/16`)
- **Subnet** `snet-vms` (`10.0.1.0/24`)
- **Network Security Group** `nsg-vms` allowing RDP from a single admin IP plus intra-subnet RDP
- **Public IPs** `pip-vm-test-1`, `pip-vm-test-2` (Standard SKU, Static)
- **Network Interfaces** `nic-vm-test-1`, `nic-vm-test-2`
- **Virtual Machines** `vm-test-1`, `vm-test-2` - Windows Server 2022 Datacenter Azure Edition, `Standard_D2s_v3`

## Repository layout

```
.
├── .gitignore
├── README.md                       <- this file
└── terraform/
    ├── .terraform.lock.hcl         <- provider version lock (committed)
    ├── compute.tf                  <- VMs, NICs, public IPs
    ├── main.tf                     <- resource group
    ├── network.tf                  <- VNet, subnet, NSG
    ├── outputs.tf                  <- required outputs
    ├── providers.tf                <- provider + remote state backend
    ├── terraform.tfvars            <- gitignored, holds admin_password
    ├── terraform.tfvars.example    <- copy to terraform.tfvars and fill in
    └── variables.tf                <- input variables
```

## Prerequisites

- Terraform `>= 1.6` (tested with 1.9.x)
- Azure CLI (`az`)
- An Azure subscription (Pay-As-You-Go; Free Trial subscriptions cannot deploy modern VM SKUs)
- A storage account for remote Terraform state (created below)

Ensure you are signed in to Azure as a user with Contributor+ permissions on the subscription:

```bash
az login
```

Create a resource group and storage account for remote state:

```bash
LOCATION="westus"
RG_NAME="rg-tfstate"
SA_NAME="elektatfstate"

az group create --name "$RG_NAME" --location "$LOCATION"

az storage account create \
  --name "$SA_NAME" \
  --resource-group "$RG_NAME" \
  --location "$LOCATION" \
  --kind StorageV2 \
  --min-tls-version TLS1_2 \
  --allow-blob-public-access false \
  --https-only true

az storage account blob-service-properties update \
  --account-name "$SA_NAME" \
  --resource-group "$RG_NAME" \
  --enable-versioning true \
  --delete-retention-days 30

az storage container create \
  --name "tfstate" \
  --account-name "$SA_NAME" \
  --auth-mode login
```

Grant your user `Storage Blob Data Contributor` on the storage account so Terraform can read/write state via AAD auth:

```bash
USER_OBJECT_ID=$(az ad signed-in-user show --query id -o tsv)
SA_ID=$(az storage account show -g "$RG_NAME" -n "$SA_NAME" --query id -o tsv)
az role assignment create --assignee "$USER_OBJECT_ID" --role "Storage Blob Data Contributor" --scope "$SA_ID"
```

## Deployment

```bash
cd terraform

# 1. Copy the example tfvars and set the admin password
cp terraform.tfvars.example terraform.tfvars

# 2. Edit terraform.tfvars to set admin_password and optionally admin_source_ip

# 3. Initialize Terraform (configures remote state)
terraform init

# 4. Plan the deployment
terraform plan

# 5. Apply the deployment
terraform apply
```

## Cleanup

To destroy the deployed resources:

```bash
terraform destroy
```

The remote state backend storage account (`rg-tfstate` / `elektatfstate`) is intentionally left intact - destroy that manually with `az group delete --name rg-tfstate` if no longer needed.

## Security notes

- The admin password is never committed - it lives only in `terraform.tfvars` (gitignored) or as the `TF_VAR_admin_password` environment variable.
- Terraform state is stored in Azure Blob Storage with TLS 1.2 minimum, public blob access disabled, AAD-only authentication, blob versioning, and 30-day soft delete.
- The NSG allows RDP only from a single configurable admin IP. Override via `admin_source_ip` in `terraform.tfvars` for any real deployment.
- For a real production deployment, public RDP would be replaced with Azure Bastion. Public IPs on VMs are kept here per the assessment requirement.
