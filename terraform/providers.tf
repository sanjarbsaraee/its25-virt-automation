# Provider runtime configuration for Infisical and Proxmox.

provider "infisical" {
  host = "https://app.infisical.com"

  # Universal Auth credentials come from three environment
  # variables set as workspace vars in HCP Terraform. An empty
  # universal block reads them automatically.
  auth = {
    universal = {}
  }
}

provider "proxmox" {
  endpoint  = var.proxmox_endpoint
  api_token = local.proxmox_api_token

  # "insecure" controls whether Terraform verifies the Proxmox API's
  # TLS cert. True skips the check; false (default) requires a cert
  # signed by a trusted CA. Proxmox uses a self-signed cert, so true.
  insecure = true

  # SSH uploads cloud-init snippets to /var/lib/vz/snippets,
  # which the Proxmox API cannot do directly.
  ssh {
    # "agent" controls whether Terraform reads keys from the local
    # SSH agent. False reads the key directly instead. HCP Terraform
    # runs in the cloud where no agent exists, so false.
    agent       = false
    username    = "terraform-bot"
    private_key = local.terraform_bot_private_key

    # Proxmox node to SSH into. Single-node setup, named "pve".
    node {
      name    = var.proxmox_node_name
      address = var.proxmox_node_address
    }
  }
}