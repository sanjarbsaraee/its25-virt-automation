# Input variables. Defaults defined here, overrides in
# terraform.tfvars or HCP Terraform workspace variables.

# ---------------------------------------------------------------------------
# Proxmox host
# ---------------------------------------------------------------------------

variable "proxmox_endpoint" {
  description = "URL to the Proxmox API, including scheme and trailing slash."
  type        = string
  default     = "https://100.94.227.10:8006/"
}

variable "proxmox_node_name" {
  description = "Proxmox node name as shown in the web UI."
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
  description = "Infisical project UUID where secrets live."
  type        = string
}

variable "infisical_environment" {
  description = "Infisical environment slug to read secrets from."
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

# ---------------------------------------------------------------------------
# LAN topology
# ---------------------------------------------------------------------------

variable "lan_subnet" {
  description = "First three octets of the LAN subnet, no trailing dot."
  type        = string
  default     = "192.168.50"
}

variable "lan_gateway" {
  description = "Gateway IP for VMs on the LAN."
  type        = string
  default     = "192.168.50.1"
}

variable "lan_bridge" {
  description = "Proxmox bridge interface name VMs attach to."
  type        = string
  default     = "vmbr0"
}