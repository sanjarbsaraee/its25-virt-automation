# Configures Terraform itself, not the infrastructure it manages.

terraform {
  # "cloud" stores state in HCP instead of a local file, so the
  # team shares one state across machines.
  cloud {
    organization = "its25-virt-automation"

    # "tags" matches all workspaces with this tag, and the CLI
    # prompts for one on init. "name" would lock to a single
    # workspace and block dev workspaces, so tags.
    workspaces {
      tags = ["its25"]
    }
  }

  # bpg/proxmox is pinned exact — 0.x minor releases are not
  # backward-compatible. Infisical uses "~> 0.16" to allow patch updates.
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