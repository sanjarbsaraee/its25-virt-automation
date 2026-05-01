# Connects Terraform to Infisical (secrets) and Proxmox (VMs).

provider "infisical" {
  host = "https://app.infisical.com"

  # Empty block picks up INFISICAL_* environment variables.
  auth = {
    universal = {}
  }
}

provider "proxmox" {
  endpoint  = var.proxmox_endpoint
  api_token = local.proxmox_api_token

  # "insecure" controls TLS cert verification. True skips
  # it. Proxmox uses a self-signed cert, so true.
  insecure = true

  # The API cannot upload cloud-init snippets, so Terraform
  # SSHs into the host to write them directly.
  ssh {
    # "agent" true uses the local SSH agent, false reads
    # private_key. HCP has no agent, so false.
    agent       = false
    username    = "terraform-bot"  # Not a human login.
    private_key = local.terraform_bot_private_key

    node {
      name    = var.proxmox_node_name
      address = var.proxmox_node_address
    }
  }
}