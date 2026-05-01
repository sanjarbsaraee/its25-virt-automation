# Configures Terraform itself, not the infrastructure.

terraform {
  # Stores state in HCP so the team shares one source of
  # truth across machines.
  cloud {
    organization = "its25-virt-automation"

    # "tags" matches workspaces tagged "its25". "name" would
    # lock to one workspace, blocking dev workspaces.
    workspaces {
      tags = ["its25"]
    }
  }

  # Proxmox pinned exact, 0.x minor releases break things.
  # Infisical uses "~>" to allow patch updates.
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.103.0"
    }
    infisical = {
      source  = "infisical/infisical"
      version = "~> 0.16"
    }
  }
}