# Engine and backend configuration. Configures Terraform itself,
# not the infrastructure it manages.

terraform {
  # "cloud" tells Terraform to store state in HCP Terraform instead
  # of a local file. State is the JSON file Terraform uses to track
  # what exists in real life. Storing it in HCP lets the team share
  # the same state across machines.
  cloud {
    organization = "its25-virt-automation"
    workspaces {
      name = "its25-virt-automation"
    }
  }

  # "required_providers" lists the plugins Terraform needs to talk
  # to external systems. bpg/proxmox is the community plugin that
  # speaks to the Proxmox API. Pinning to an exact version protects
  # against breaking changes between 0.x minor releases.
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.103.0"
    }
  }
}