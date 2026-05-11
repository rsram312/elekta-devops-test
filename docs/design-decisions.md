# Design Decisions and Assumptions

## Assumptions

1. **Single resource group for workload.** The assessment specifies one Resource Group named `elekta-devops-test`. All workload resources (networking, compute) live in it. The Terraform state storage account lives in a separate, pre-existing RG (`rg-tfstate`) created by one-time bootstrap - mixing state storage with workload resources is a bad idea because destroying the workload could destroy your state.
2. **Region.** Defaulted to `westus` (Northern California datacenters) because the operator is in Northern California; latency to the VMs matters for RDP. The `location` variable is parameterized so this can be changed via tfvars.
3. **VM size.** `Standard_D2s_v3` (2 vCPU, 8 GB RAM, Intel). Chosen after `Standard_B2s`, `Standard_B2as_v2`, and `Standard_D2s_v5` all returned `SkuNotAvailable` in westus and westus3 - D2s_v3 was the only family with both quota and current capacity in westus.
4. **OS image.** `MicrosoftWindowsServer / WindowsServer / 2022-datacenter-azure-edition / latest`. The "Azure Edition" image is the modern default for Windows Server 2022 on Azure and supports newer features like Hot Patching.
5. **VM-to-VM RDP.** Both VMs sit in the same subnet, so by default they can talk to each other on any port. An explicit intra-subnet NSG allow rule for RDP was added so the requirement still holds if the subnet is later split or extra NSG rules are added. Verified manually: RDP'd from Mac to vm-test-1, then from vm-test-1 to vm-test-2 over the 10.0.1.0/24 subnet.
6. **External RDP.** Each VM has a Public IP per the assessment. The NSG only allows RDP from `admin_source_ip` (a single configurable CIDR), defaulted to the operator's home IP `108.85.28.184/32` during development. Verified: external RDP from Mac to vm-test-1 worked.
7. **Credentials.** Username / Password as specified by the assessment. The password is never committed - supplied as `TF_VAR_admin_password` via a gitignored `terraform.tfvars` locally or a secret variable group in Azure DevOps.
8. **Pipeline platform.** Azure DevOps, per the assessment's primary path. Pipeline source is the GitHub repository - the assessment allows either GitHub or Azure DevOps for source control, and code-in-GitHub + pipeline-in-Azure-DevOps is a common industry pattern. To use the Azure DevOps pipeline on a new free organization, a $40/month Microsoft-hosted parallel job was purchased to skip the 2-5 business day approval delay for free grants.

## Why a flat module structure

The brief is small enough that a single flat directory of `.tf` files is the right call. No child modules. Reasons:

- Two VMs and a single VNet do not warrant the abstraction overhead of modules.
- Modules add value when the same shape needs to be reused, parameterized, or shared across teams. Neither applies here.
- A flat structure is faster to read and review for a take-home assessment.

A `modules/` split was considered and intentionally rejected; in a production codebase with multiple workloads or environments it would become the right call.

## State management

State is stored in an Azure Storage Account (created by a one-time `az` CLI bootstrap):

- Per-workload state blob key (`elekta-devops-test.tfstate`).
- AAD authentication (`use_azuread_auth = true`) - no storage keys handed around.
- Blob versioning + 30-day soft delete - state is recoverable.
- TLS 1.2 minimum, HTTPS-only, public blob access disabled.
- Backend resource group (`rg-tfstate`) and storage account (`elektatfstate`) are deliberately not managed by this Terraform configuration - they bootstrap it.

## Security trade-offs

| Decision | What we did | What we'd do for production |
| --- | --- | --- |
| RDP exposure | NSG locked to `admin_source_ip` | Replace public IPs with Azure Bastion; remove inbound RDP from the public internet entirely. |
| Admin credentials | Pipeline secret variable + gitignored tfvars | Store in Key Vault, fetch via `azurerm_key_vault_secret` data source or use SSH key / Entra-domain join. |
| Password rotation | None | Rotate via Key Vault and trigger re-deploy. |
| OS patching | `AutomaticByOS` (implicit default) | Use Azure Update Manager + maintenance windows. |
| Diagnostics / logs | Not configured | Enable VM Insights + send NSG flow logs to a Log Analytics workspace. |
| Identity | Local admin only | System-assigned managed identity on each VM. |
| Disk encryption | Platform-managed keys (default) | Customer-managed keys (CMK) via Azure Key Vault. |
| Authorization for state | RBAC on storage account | Tighter conditional access (IP-bound, MFA-required for non-pipeline access). |

## Pipeline trade-offs

- **OIDC over service principal secrets.** Federated workload identity removes the need to store and rotate a client secret. Required one-time configuration to create the Azure RM service connection.
- **Plan artifact reused by apply.** The apply stage downloads the exact plan produced in the plan stage rather than re-planning. This is the standard "review the plan, apply that plan" pattern - it removes the risk of an unreviewed change slipping in between plan and apply.
- **Approval gate via Environments, not job-level intervention.** Putting approval on the Azure DevOps Environment (rather than a manual job-intervention step) keeps the approval policy in one place and lets the same gate apply to any pipeline that targets `prod`.
- **Publish only the `tfplan` file, not the working directory.** Publishing `.terraform/` in the artifact strips the executable bit from provider binaries during artifact transfer, breaking the apply. The fix is to publish only the `tfplan` file; the apply stage re-runs `terraform init` and gets a fresh provider binary with correct permissions.

## What's intentionally not in scope

- Active Directory / domain join - not in the brief.
- Backups (Azure Backup vault) - not in the brief.
- Monitoring / alerting - not in the brief but worth adding for any non-trivial environment.
- Multi-region or HA - not in the brief; both VMs are in a single zone for simplicity. For real workloads they'd be split across availability zones via the `zone` argument or placed in an availability set.
- Multi-environment (dev/prod) Terraform structure. The pipeline has `prod` and `dev` Environments for approval gating, but a single state and tfvars are used. A real environment would split state keys per environment and gate the pipeline on an `environment` parameter.

## What this work covers vs. the assessment

| Assessment requirement | Where it's done |
| --- | --- |
| Resource Group `elekta-devops-test` | `terraform/main.tf` |
| VNet + subnet for VMs | `terraform/network.tf` |
| NSG allowing RDP | `terraform/network.tf` |
| Two Windows Server 2022 VMs | `terraform/compute.tf` |
| VMs RDP each other | NSG intra-subnet rule + same-subnet placement |
| Public IPs | `terraform/network.tf` |
| Outputs (VM names, public IPs, private IPs, RG name) | `terraform/outputs.tf` |
| Source control repository | GitHub `rsram312/elekta-devops-test` |
| Organized Terraform files | Flat `.tf` files, one per concern |
| README with deployment instructions | `README.md` |
| CI/CD pipeline (validate / plan / apply) | `azure-pipelines.yml` |
| Production approval | Azure DevOps `prod` Environment with manual approval check |
| Secure state storage | Azure Blob Storage, AAD auth, TLS 1.2, versioning, soft-delete |
| Variables for environment-specific values | `terraform/variables.tf` (location, RG name, network CIDRs, VM size, admin IP, tags) |
| Security measures | NSG locked to admin IP; secrets in pipeline variable group; OIDC federation; sensitive var marking |
| Pipeline documentation | `docs/pipeline.md` |
| Assumptions explained | This file |