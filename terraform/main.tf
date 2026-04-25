terraform {
  cloud {
    organization = "its25-virt-automation"
    workspaces {
      name = "its25-virt-automation"
    }
  }

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.68.0"
    }
  }
}

variable "api_token" {
  description = "Proxmox API Token"
  type        = string
  sensitive   = true
}

variable "ssh_username" {
  description = "Proxmox OS username used by Terraform for SSH"
  type        = string
}

variable "ssh_private_key" {
  description = "Path to the local SSH private key authorized on the Proxmox host"
  type        = string
}

variable "jim_vm_public_key" {
  description = "Jim's public SSH key, injected into provisioned VMs"
  type        = string
}

variable "sanjar_vm_public_key" {
  description = "Sanjar's public SSH key, injected into provisioned VMs"
  type        = string
}

provider "proxmox" {
  endpoint  = "https://100.94.227.10:8006/"
  api_token = var.api_token

  # Proxmox ships with a self-signed certificate by default. Replacing it with
  # a trusted certificate is out of scope for the initial iterations. The
  # connection is protected by the Tailscale tunnel rather than by TLS trust.
  insecure = true

  ssh {
    agent       = false
    username    = var.ssh_username
    private_key = file(var.ssh_private_key)

    node {
      name    = "pve"
      address = "100.94.227.10"
    }
  }
}

resource "proxmox_virtual_environment_vm" "control_node" {
  name      = "control-node"
  node_name = "pve"
  vm_id     = 510

  # Template 9000 does not include qemu-guest-agent. Enabling this would cause
  # Terraform to wait indefinitely for an agent that never responds.
  agent {
    enabled = false
  }

  clone {
    vm_id = 9000
    full  = true
  }

  cpu {
    cores = 2
  }

  memory {
    dedicated = 2048
  }

  network_device {
    bridge = "vmbr0"
  }

  initialization {
    ip_config {
      ipv4 {
        address = "192.168.50.10/24"
        gateway = "192.168.50.1"
      }
    }
    user_account {
      username = "admin"
      keys = [
        var.jim_vm_public_key,
        var.sanjar_vm_public_key,
      ]
    }
  }
}