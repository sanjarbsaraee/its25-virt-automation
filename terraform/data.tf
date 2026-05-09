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

  # Individual keys
  sanjar_key     = data.infisical_secrets.proxmox.secrets["SANJAR_VM_PUBLIC_KEY"].value
  jim_key        = data.infisical_secrets.proxmox.secrets["JIM_VM_PUBLIC_KEY"].value
  automation_key = data.infisical_secrets.proxmox.secrets["AUTOMATION_PUBLIC_KEY"].value

  # List used for VM creation
  vm_admin_public_keys = [
    local.sanjar_key,
    local.jim_key,
    local.automation_key,
  ]

  # Automation key for control-node to worker-node communication.
  automation_private_key = data.infisical_secrets.proxmox.secrets["AUTOMATION_PRIVATE_KEY"].value

  db_password = data.infisical_secrets.proxmox.secrets["DB_PASSWORD"].value
}
