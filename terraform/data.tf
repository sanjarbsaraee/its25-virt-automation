# Data sources and computed values. Reads secrets from Infisical
# and public SSH keys from the .ssh directory.

data "infisical_secrets" "proxmox" {
  env_slug     = var.infisical_environment
  workspace_id = var.infisical_project_id
  folder_path  = "/"
}

locals {
  # Pulls the Proxmox API token out of the Infisical response so
  # providers.tf can reference it as a single value.
  proxmox_api_token = data.infisical_secrets.proxmox.secrets["PROXMOX_API_TOKEN"].value

  # The terraform-bot SSH private key for connecting to the Proxmox
  # host. Lives in Infisical so the key never touches disk in CI
  # or HCP runners.
  terraform_bot_private_key = data.infisical_secrets.proxmox.secrets["TERRAFORM_BOT_PRIVATE_KEY"].value

  # Public SSH keys live in .ssh/ next to this Terraform config.
  # Reading them with file() means the keys exist in only one place,
  # and updating a key needs no Terraform code change.
  # trimspace() strips trailing newlines that text editors add.
  vm_admin_public_keys = [
    trimspace(file("${path.module}/.ssh/sanjar_vm_key.pub")),
    trimspace(file("${path.module}/.ssh/jim_vm_key.pub")),
  ]
}