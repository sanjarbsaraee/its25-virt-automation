# Reads secrets from Infisical and SSH public keys from disk.

# "infisical_secrets" pulls the project's secrets in one call.
# providers.tf and main.tf reference values via locals below.
data "infisical_secrets" "proxmox" {
  env_slug     = var.infisical_environment
  workspace_id = var.infisical_project_id
  folder_path  = "/"
}

locals {
  # Proxmox API token used by the bpg/proxmox provider.
  proxmox_api_token = data.infisical_secrets.proxmox.secrets["PROXMOX_API_TOKEN"].value

  # Private key the provider uses for SSH against the Proxmox
  # host. Stored in Infisical so it never lands on disk locally.
  terraform_bot_private_key = data.infisical_secrets.proxmox.secrets["TERRAFORM_BOT_PRIVATE_KEY"].value

  # Public keys for human SSH into the VMs. Reading from disk
  # keeps the source of truth in .ssh/ rather than HCL.
  # "trimspace" drops the trailing newline editors append.
  vm_admin_public_keys = [
    trimspace(file("${path.module}/.ssh/sanjar_vm_key.pub")),
    trimspace(file("${path.module}/.ssh/jim_vm_key.pub")),
  ]
}