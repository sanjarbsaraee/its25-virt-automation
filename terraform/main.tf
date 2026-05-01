# VMs and supporting resources on the Proxmox host.

# Each workspace gets unique VM IDs and IPs so dev VMs
# never collide with main or each other. Offsets (+10,
# +20, +30) leave room for future VMs in each tier.
locals {
  env_config = {
    "its25-virt-automation" = { name_suffix = "",        vm_base = 500, ip_base = 0 }
    "its25-sanjar-dev"      = { name_suffix = "-sanjar", vm_base = 600, ip_base = 100 }
    "its25-jim-dev"         = { name_suffix = "-jim",    vm_base = 700, ip_base = 200 }
  }

  # Falls back to main if the workspace name is unknown,
  # preventing accidental ID collisions.
  env = lookup(local.env_config, terraform.workspace, local.env_config["its25-virt-automation"])
}

# Uploads the cloud-init YAML that configures the control-node:
# admin user, SSH keys, packages and repo clone.
resource "proxmox_virtual_environment_file" "ansible_bootstrap" {
  content_type = "snippets"  # Stored in /var/lib/vz/snippets/ on the host.
  datastore_id = "local"
  node_name    = var.proxmox_node_name

  source_raw {
    # Substitutes SSH public keys into the YAML template.
    data = templatefile("${path.module}/ansible-bootstrap.yaml", {
      sanjar_key = data.infisical_secrets.proxmox.secrets["SANJAR_VM_PUBLIC_KEY"].value,
      jim_key    = data.infisical_secrets.proxmox.secrets["JIM_VM_PUBLIC_KEY"].value,
    })
    file_name = "ansible-bootstrap.yaml"
  }
}

# Runs Ansible playbooks against the other VMs. Configured
# by ansible-bootstrap.yaml at first boot.
resource "proxmox_virtual_environment_vm" "control_node" {
  name      = "control-node${local.env.name_suffix}"
  node_name = var.proxmox_node_name
  vm_id     = local.env.vm_base + 10

  # "enabled" controls whether Proxmox queries qemu-guest-agent
  # inside the VM. True asks for IPs and runs commands. The
  # Debian cloud-image lacks the agent, so false.
  agent {
    enabled = false
  }

  clone {
    vm_id = var.template_vm_id
    # "full" copies the entire disk. False creates a linked
    # clone tied to the template. Full is independent, so true.
    full = true
  }

  cpu {
    cores = 2
  }

  # 2048 fits Ansible plus iter 1 services.
  memory {
    dedicated = 2048
  }

  network_device {
    # A bridge is a virtual switch that connects VMs to the
    # physical network.
    bridge = var.lan_bridge
    # "virtio" is a paravirtualized driver built into the cloud
    # image. "e1000" emulates physical hardware, ~30% slower.
    model = "virtio"
  }

  initialization {
    # The bootstrap snippet sets users, packages and SSH keys.
    # This block adds what cloud-init cannot: static IP and DNS.
    user_data_file_id = proxmox_virtual_environment_file.ansible_bootstrap.id

    ip_config {
      ipv4 {
        address = "${var.lan_subnet}.${local.env.ip_base + 10}/24"
        gateway = var.lan_gateway
      }
    }

    # Proxmox inherits Tailscale MagicDNS from the host's
    # resolv.conf. That resolver cannot reach deb.debian.org.
    dns {
      servers = ["1.1.1.1", "8.8.8.8"]
    }
  }

  # Cloud-init changes fields after first boot, and Proxmox
  # regenerates the MAC on clone. Without this, Terraform
  # would plan changes that are not real.
  lifecycle {
    ignore_changes = [
      network_device,
    ]
  }
}

# Iter 2 web server. Hosts Nginx.
resource "proxmox_virtual_environment_vm" "web_01" {
  name        = "web-01${local.env.name_suffix}"
  node_name   = var.proxmox_node_name
  vm_id       = local.env.vm_base + 20
  description = "Iteration 2 web server (Nginx)."

  agent {
    enabled = false
  }

  clone {
    vm_id = var.template_vm_id
    full  = true
  }

  cpu {
    cores = 2
  }

  # 1024 fits Nginx plus a small static site.
  memory {
    dedicated = 1024
  }

  network_device {
    bridge = var.lan_bridge
    model  = "virtio"
  }

  initialization {
    ip_config {
      ipv4 {
        address = "${var.lan_subnet}.${local.env.ip_base + 20}/24"
        gateway = var.lan_gateway
      }
    }

    # SSH keys via cloud-init. The control-node uses
    # ansible-bootstrap.yaml instead.
    user_account {
      username = "admin"
      keys     = local.vm_admin_public_keys
    }
  }

  # Same drift issue as control-node. user_account also
  # changes after cloud-init runs.
  lifecycle {
    ignore_changes = [
      network_device,
      initialization[0].user_account,
    ]
  }
}

# Iter 2 database server. Hosts PostgreSQL 16.
resource "proxmox_virtual_environment_vm" "db_01" {
  name        = "db-01${local.env.name_suffix}"
  node_name   = var.proxmox_node_name
  vm_id       = local.env.vm_base + 30
  description = "Iteration 2 database server (PostgreSQL 16)."

  agent {
    enabled = false
  }

  clone {
    vm_id = var.template_vm_id
    full  = true
  }

  cpu {
    cores = 2
  }

  # 1024 covers PostgreSQL with a small dataset.
  memory {
    dedicated = 1024
  }

  # Separate disk for database storage.
  disk {
    datastore_id = "local-lvm"
    interface    = "scsi0"
    size         = 20
  }

  network_device {
    bridge = var.lan_bridge
    model  = "virtio"
  }

  initialization {
    ip_config {
      ipv4 {
        address = "${var.lan_subnet}.${local.env.ip_base + 30}/24"
        gateway = var.lan_gateway
      }
    }

    user_account {
      username = "admin"
      keys     = local.vm_admin_public_keys
    }
  }

  lifecycle {
    ignore_changes = [
      network_device,
      initialization[0].user_account,
    ]
  }
}