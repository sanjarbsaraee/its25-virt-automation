# Declares every value the config needs. Defaults cover
# the common case, terraform.tfvars overrides per machine.

# ---------------------------------------------------------------------------
# Proxmox host
# ---------------------------------------------------------------------------

variable "proxmox_endpoint" {
  description = "URL to the Proxmox API, e.g. https://10.0.0.1:8006/"
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
  description = "Project ID from Infisical UI, Settings tab."
  type        = string
}

variable "infisical_environment" {
  description = "Infisical environment to read secrets from."
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
  description = "First three numbers of the LAN IP, e.g. 192.168.50"
  type        = string
  default     = "192.168.50"
}

variable "lan_gateway" {
  description = "Default route for VMs on the LAN."
  type        = string
  default     = "192.168.50.1"
}

variable "lan_bridge" {
  description = "Proxmox virtual switch that connects VMs to the network."
  type        = string
  default     = "vmbr0"
}