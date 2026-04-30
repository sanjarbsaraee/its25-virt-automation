# Provider runtime configuration for Infisical and Proxmox.

provider "infisical" {
  host = "https://app.infisical.com"

  # An empty universal block reads three INFISICAL_* env vars
  # automatically.
  auth = {
    universal = {}
  }
}

provider "proxmox" {
  endpoint  = var.proxmox_endpoint
  api_token = local.proxmox_api_token

  # "insecure" controls TLS cert verification of the Proxmox API.
  # True skips it, false (default) requires a valid cert. Proxmox
  # uses self-signed, so true.
  insecure = true

  # SSH uploads cloud-init snippets to /var/lib/vz/snippets, which
  # the Proxmox API cannot do directly.
  ssh {
    # "agent" picks the SSH key source. True uses the local agent,
    # false reads private_key directly. HCP has no agent, so false.
    agent       = false
    username    = "terraform-bot"
    private_key = local.terraform_bot_private_key

    node {
      name    = var.proxmox_node_name
      address = var.proxmox_node_address
    }
  }
}