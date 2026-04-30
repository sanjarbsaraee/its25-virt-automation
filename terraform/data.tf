# Reads secrets from Infisical and SSH public keys from disk.

# Pulls all project secrets in one API call.
data "infisical_secrets" "proxmox" {
  env_slug     = var.infisical_environment
  workspace_id = var.infisical_project_id
  folder_path  = "/"
}

locals {
  proxmox_api_token = data.infisical_secrets.proxmox.secrets["PROXMOX_API_TOKEN"].value

  # SSH key the provider uses for the Proxmox host. Stored in
  # Infisical so it never lands on local disk.
  terraform_bot_private_key = data.infisical_secrets.proxmox.secrets["TERRAFORM_BOT_PRIVATE_KEY"].value

  # Public keys for Sanjar and Jim, read from .ssh/. trimspace
  # strips the trailing newline editors add — without it
  # Terraform sees a diff and re-applies on every run.
  vm_admin_public_keys = [
    trimspace(file("${path.module}/.ssh/sanjar_vm_key.pub")),
    trimspace(file("${path.module}/.ssh/jim_vm_key.pub")),
  ]
}