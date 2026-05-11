# Pipeline Documentation

Detailed walkthrough of the Azure DevOps pipeline defined in `azure-pipelines.yml`.

## Goals

1. Validate every change before it touches Azure.
2. Make every change reviewable - the plan is published as a pipeline artifact.
3. Gate production applies behind explicit human approval.
4. Authenticate to Azure with no long-lived secrets.
5. Store state remotely with versioning + soft delete so it can be recovered if corrupted.

## Stages

### Stage 1 - Validate

Runs on every push to `main` and on every PR.

| Step | Purpose |
| --- | --- |
| `terraform fmt -check -recursive` | Fails the build if any `.tf` file isn't canonically formatted. |
| `terraform init` (against the remote backend) | Catches misconfigured backend, missing RBAC, or network issues early. |
| `terraform validate` | Schema-level HCL validation. |

If Validate fails, Plan and Apply do not run.

### Stage 2 - Plan

Runs after Validate succeeds.

| Step | Purpose |
| --- | --- |
| `terraform init` | Re-initialize on the fresh agent (each job runs on a clean Microsoft-hosted VM; nothing persists between stages). |
| `terraform plan -out=tfplan` | Generate the plan file. |
| `terraform show -no-color tfplan > tfplan.txt` | Produce a human-readable plan summary for review. |
| Publish artifact `tfplan` | Save the exact plan file so the Apply stage uses the reviewed plan. |

### Stage 3 - Apply

Runs only on `main` branch builds (not PRs). Bound to the `prod` Azure DevOps Environment, so the manual approval check on that environment gates execution.

| Step | Purpose |
| --- | --- |
| Download `tfplan` artifact | Use the same plan that was reviewed and approved. |
| `terraform init` | Required again on the fresh agent. |
| `terraform apply -auto-approve tfplan` | Apply the saved plan. No `-var-file` needed; the plan already encodes inputs. |
| `terraform output -json > tf-outputs.json` + publish artifact `tf-outputs` | Capture resource outputs for downstream automation. |

## Authentication

The pipeline authenticates to Azure using **Workload Identity Federation (OIDC)**. The service connection's federated identity maps to ARM environment variables:

- `ARM_CLIENT_ID`
- `ARM_OIDC_TOKEN`
- `ARM_TENANT_ID`
- `ARM_SUBSCRIPTION_ID` (resolved via `az account show`)

The same federated identity is used to access blob state. No storage account key is handed to the pipeline.

## State management

| Setting | Value | Why |
| --- | --- | --- |
| Container | `tfstate` | Standard name for Terraform state. |
| Key | `elekta-devops-test.tfstate` | Unique per deployment; multiple environments would use different keys. |
| Auth | `use_azuread_auth = true` | RBAC-controlled, no shared keys. |
| Versioning | Enabled | Recover from accidental state corruption. |
| Soft delete | 30 days | Recover from accidental container/blob deletes. |
| TLS | 1.2 minimum, HTTPS only | State is never public. |

## One-time Azure DevOps setup

The pipeline assumes the following resources exist in the Azure DevOps organization and project:

### 1. Marketplace extension - "Azure Pipelines Terraform Tasks" (ms-devlabs)

Install at the organization level. Provides the `TerraformInstaller@1` task.

### 2. Service connection (Azure RM) - `azure-elekta-devops`

Project settings -> Service connections -> New service connection -> Azure Resource Manager -> Workload Identity federation (automatic) -> Subscription scope -> Save as `azure-elekta-devops`.

After creation, grant the auto-created Service Principal `Storage Blob Data Contributor` on the state storage account:

```bash
# Get the SP Object ID from "Manage Service Principal" -> Enterprise Applications -> Object ID
SP_OBJECT_ID="<paste-here>"

# Grant role
SA_ID=$(az storage account show -g "rg-tfstate" -n "elektatfstate" --query id -o tsv)
az role assignment create --assignee-object-id "$SP_OBJECT_ID" --assignee-principal-type ServicePrincipal --role "Storage Blob Data Contributor" --scope "$SA_ID"
```

### 3. Environment - `prod`

Pipelines -> Environments -> New environment -> Name: `prod` -> Manual approval -> Add yourself as approver.

### 4. Variable group - `elekta-devops-secrets`

Pipelines -> Library -> Variable groups -> New variable group -> Name: `elekta-devops-secrets` -> Add variable `TF_VAR_admin_password` (padlock icon). Value is the VM admin password.

The `TF_VAR_` prefix means Terraform automatically picks it up as a variable. Link this variable group to the pipeline.

## Failure modes worth knowing

### `terraform fmt -check` fails
Local code is not canonically formatted. Run `terraform fmt -recursive` locally and commit.

### `terraform init` fails with 403 / AuthorizationPermissionMismatch
The pipeline's Service Principal lacks `Storage Blob Data Contributor` on the state storage account. Re-run the role assignment in setup step 2.

### `terraform plan` shows unexpected changes
State has drifted from what's in the code (someone changed something in the portal, or a previous apply failed partway). Inspect the plan output before approving the apply.

### Provider binary "permission denied" in apply stage
Caused by publishing the entire working directory (including `.terraform/`) as the artifact - file modes get lost in the tar/zip. The pipeline publishes only the `tfplan` file itself, not the directory, to avoid this.

### Plan stage takes 5+ minutes
First run on a fresh Microsoft-hosted agent downloads the AzureRM provider plugin (~80 MB). Subsequent runs on a different agent will do the same - agents are ephemeral. This is by design.

### Long queue before any stage starts
Microsoft-hosted parallel job not yet provisioned, or all parallel jobs are in use. Wait or upgrade the organization.

## Future improvements

- **Multi-environment support**: The pipeline deploys a single environment. Multi-environment support would split state by key (`elekta-devops-test/<env>.tfstate`) and parameterize the pipeline with an `environment` parameter.
- **Secrets management**: Move secrets from variable groups to Azure Key Vault references.
