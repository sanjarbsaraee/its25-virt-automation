terraform {
    cloud {
    organization = "proxmox-automation"
        workspaces {
            name = "proxmox-automation"
        }
    }
    required_providers {
    proxmox = {
        source  = "bpg/proxmox"
        version = "0.68.0"
    }
    tls = {
        source  = "hashicorp/tls"
        version = "4.0.5"
    }
    local = {
        source  = "hashicorp/local"
        version = "2.5.1"
    }
    }
}

variable "api_token" {
  description = "Proxmox API Token"
  type        = string
  sensitive   = true
}

provider "proxmox" {
  endpoint  = "https://100.94.227.10:8006/"
  api_token = var.api_token
  insecure  = true

  ssh {
    agent       = false
    username    = "jim"
    private_key = file("../.ssh/proxmox_key")
    
    node {
      name    = "pve"
      address = "100.94.227.10"
    }
  }
}

resource "tls_private_key" "vm_key" {
  algorithm = "ED25519"
}

resource "local_sensitive_file" "vm_private_key_file" {
  content         = tls_private_key.vm_key.private_key_openssh
  filename        = "../.ssh/vm_key"
  file_permission = "0600"
}

resource "proxmox_virtual_environment_vm" "lab_vm" {
  name      = "debian-lab-01"
  node_name = "pve"
  vm_id     = 510

  agent {
    enabled = false
  }

  clone {
    vm_id = 9000
    full  = true
  }

  initialization {
    ip_config {
      ipv4 {
        address = "192.168.50.60/24"
        gateway = "192.168.50.1"
      }
    }
    user_account {
      username = "admin"
      keys     = [tls_private_key.vm_key.public_key_openssh]
    }
  }
}