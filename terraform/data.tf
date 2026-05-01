# Pulls secrets from Infisical into local variables.
# Nothing sensitive lives in the repo or on local disk.

# Fetches all secrets in one call. Individual values
# are mapped to short names in locals below.
data "infisical_secrets" "proxmox" {
  env_slug     = var.infisical_environment
  workspace_id = var.infisical_project_id
  folder_path  = "/"
}

locals {
  # Authenticates Terraform against the Proxmox API.
  proxmox_api_token = data.infisical_secrets.proxmox.secrets["PROXMOX_API_TOKEN"].value

  # Private key the provider uses to SSH into the host.
  terraform_bot_private_key = data.infisical_secrets.proxmox.secrets["TERRAFORM_BOT_PRIVATE_KEY"].value

  # Public keys injected into VMs for human SSH access.
  vm_admin_public_keys = [
    data.infisical_secrets.proxmox.secrets["SANJAR_VM_PUBLIC_KEY"].value,
    data.infisical_secrets.proxmox.secrets["JIM_VM_PUBLIC_KEY"].value,
  ]
}
