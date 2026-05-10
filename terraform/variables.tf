# ----------------------------------------------------------------------------
# Location and resource group
# ----------------------------------------------------------------------------

variable "location" {
  description = "Azure region for all resources."
  type        = string
  default     = "westus"
}

variable "resource_group_name" {
  description = "Name of the resource group containing all infrastructure."
  type        = string
  default     = "elekta-devops-test"
}

# ----------------------------------------------------------------------------
# Networking
# ----------------------------------------------------------------------------

variable "vnet_address_space" {
  description = "Address space (CIDR list) for the Virtual Network."
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "subnet_address_prefixes" {
  description = "Address prefixes (CIDR list) for the VM subnet."
  type        = list(string)
  default     = ["10.0.1.0/24"]
}

variable "admin_source_ip" {
  description = "Public IP allowed to RDP to the VMs (CIDR notation, e.g. '203.0.113.10/32')."
  type        = string
  default     = "108.85.28.184/32"
}

# ----------------------------------------------------------------------------
# Compute
# ----------------------------------------------------------------------------

variable "vm_size" {
  description = "Azure VM size for both VMs."
  type        = string
  default     = "Standard_D2s_v3"
}

variable "admin_username" {
  description = "Local administrator username for the VMs."
  type        = string
  default     = "Elekta"
}

variable "admin_password" {
  description = "Local administrator password for the VMs. Provide via terraform.tfvars (gitignored) or TF_VAR_admin_password."
  type        = string
  sensitive   = true
}

# ----------------------------------------------------------------------------
# Tagging
# ----------------------------------------------------------------------------

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default = {
    Workload  = "elekta-devops-test"
    ManagedBy = "Terraform"
  }
}