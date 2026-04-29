# Configures Terraform itself, not the infrastructure it manages.
 
terraform {
  # "cloud" stores state in HCP Terraform instead of a local file.
  # The team shares one state across machines that way.
  cloud {
    organization = "its25-virt-automation"
 
    # "tags" matches all workspaces with this tag. The CLI prompts
    # for a workspace on init. "name" would lock to one workspace
    # and block per-developer dev workspaces, so tags.
    workspaces {
      tags = ["its25"]
    }
  }
 
  # Pinning bpg/proxmox to an exact version protects against
  # breaking changes between 0.x minor releases. Infisical uses
  # "~> 0.16" to allow patch updates.
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