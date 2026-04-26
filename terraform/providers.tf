# Provider runtime configuration. Tells the bpg/proxmox plugin
# how to reach the Proxmox host and how to authenticate.

provider "infisical" {
  host = "https://app.infisical.com"

  # Authentication uses Universal Auth via three environment variables
  # set as workspace variables in HCP Terraform:
  #   INFISICAL_UNIVERSAL_AUTH_CLIENT_ID
  #   INFISICAL_UNIVERSAL_AUTH_CLIENT_SECRET
  #   INFISICAL_MACHINE_IDENTITY_ID
  # Leaving the universal block empty lets the provider read those
  # values from the environment automatically.
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

  # The plugin uses SSH for operations the API can't handle. The API
  # creates and configures VMs. SSH uploads files such as cloud-init
  # snippets to the host's snippets directory.
  ssh {
    # "agent" controls whether Terraform reads keys from the local
    # SSH agent. False reads the key directly instead. HCP Terraform
    # runs in the cloud where no agent exists, so false.
    agent       = false
    username    = "terraform-bot"
    private_key = local.terraform_bot_private_key

    # "node" tells the plugin which Proxmox node to SSH into. A
    # cluster can have multiple nodes. This project has one node
    # named "pve" at the same Tailscale IP as the API endpoint.
    node {
      name    = var.proxmox_node_name
      address = var.proxmox_node_address
    }
  }
}