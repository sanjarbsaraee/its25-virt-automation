# Input variables. Values come from terraform.tfvars locally, or
# workspace variables in HCP Terraform when run in the cloud.

# ---------------------------------------------------------------------------
# Proxmox host
# ---------------------------------------------------------------------------

variable "proxmox_endpoint" {
  description = "URL to the Proxmox API, including scheme and trailing slash."
  type        = string
  default     = "https://100.94.227.10:8006/"
}

variable "proxmox_node_name" {
  description = "Name of the Proxmox node as it appears in the web UI. Default for a single-node install is 'pve'."
  type        = string
  default     = "pve"
}

variable "proxmox_node_address" {
  description = "IP or hostname Terraform uses to SSH into the Proxmox node."
  type        = string
  default     = "100.94.227.10"
}

# ---------------------------------------------------------------------------
# Infisical
# ---------------------------------------------------------------------------

variable "infisical_project_id" {
  description = "Infisical project ID where secrets live. Found in Infisical UI under project Settings."
  type        = string
}

variable "infisical_environment" {
  description = "Infisical environment slug, e.g. 'dev'. Found in Infisical UI under Environments."
  type        = string
  default     = "dev"
}

# ---------------------------------------------------------------------------
# Proxmox template
# ---------------------------------------------------------------------------

variable "template_vm_id" {
  description = "VM ID of the Debian 12 cloud-init template to clone."
  type        = number
  default     = 9000
}