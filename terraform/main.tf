# Resources. Defines what Terraform creates on the Proxmox host.

locals {
  # Environment Configuration Map
  # This map dynamically scales our infrastructure across multiple developer workspaces
  # without IP or VM ID collisions on the shared Proxmox host.
  #
  # How it works:
  # - name_suffix: Appended to VM names to identify the owner (e.g., web-01-jim).
  # - vm_base: The starting Proxmox ID for this environment. A VM's final ID is vm_base + offset (e.g., control_node = vm_base + 10).
  # - ip_base: The offset added to the last octet of the IP. (e.g., 192.168.50.<ip_base + offset>).
  env_config = {
    "its25-virt-automation" = { name_suffix = "", vm_base = 500, ip_base = 0 }
    "its25-sanjar-dev"      = { name_suffix = "-sanjar", vm_base = 600, ip_base = 100 }
    "its25-jim-dev"         = { name_suffix = "-jim", vm_base = 700, ip_base = 200 }
  }

  # Fallback to main if workspace isn't found
  env = lookup(local.env_config, terraform.workspace, local.env_config["its25-virt-automation"])
}

# Cloud-init snippet for the control_node VM below.
resource "proxmox_virtual_environment_file" "ansible_bootstrap" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = var.proxmox_node_name

  source_raw {
    # "templatefile" reads the YAML and substitutes ${ }
    # markers. Both public keys land in the snippet.
    data = templatefile("${path.module}/ansible-bootstrap.yaml", {
      sanjar_key = file("${path.module}/.ssh/sanjar_vm_key.pub"),
      jim_key    = file("${path.module}/.ssh/jim_vm_key.pub"),
    })
    file_name = "ansible-bootstrap.yaml"
  }
}

# ===========================================================================
# === Control-node VM =======================================================
# ===========================================================================
# Control-node VM. Cloned from template 9000 and configured
# from the ansible_bootstrap snippet on first boot.
resource "proxmox_virtual_environment_vm" "control_node" {
  # Workspace-aware naming. Default workspace builds production
  # control-node. Dev workspaces append the workspace name so
  # parallel dev VMs do not collide with each other or main.
  name      = "control-node${local.env.name_suffix}"
  node_name = var.proxmox_node_name

  # Workspace-aware vm_id.
  vm_id = local.env.vm_base + 10

  # "enabled" controls whether Proxmox queries qemu-guest-agent.
  # True asks the VM for IPs. False skips the call. Template
  # 9000 lacks the agent, so false.
  agent {
    enabled = false
  }

  clone {
    vm_id = var.template_vm_id

    # "full" picks clone mode. True copies the whole disk.
    # False shares blocks via copy-on-write. Full is independent
    # of the template, so true.
    full = true
  }

  cpu {
    cores = 2
  }

  # Memory in MiB. 2048 fits Ansible plus iter 1 services.
  memory {
    dedicated = 2048
  }

  network_device {
    bridge = "vmbr0"

    # "virtio" uses the paravirtualized driver shipped with
    # the Debian cloud image. "e1000" emulates a real NIC and
    # is slower, so virtio.
    model = "virtio"
  }

  initialization {
    # Snippet drives users, packages, and SSH keys. The block
    # here only sets what the snippet cannot: static IP and DNS.
    user_data_file_id = proxmox_virtual_environment_file.ansible_bootstrap.id

    ip_config {
      ipv4 {
        # Workspace-aware IP.
        address = "192.168.50.${local.env.ip_base + 10}/24"
        gateway = "192.168.50.1"
      }
    }

    # Proxmox pushes the host's resolv.conf into cloud-init,
    # which sets eth0 DNS to Tailscale MagicDNS. That resolver
    # answers tailnet names, not deb.debian.org, so override.
    dns {
      servers = ["1.1.1.1", "8.8.8.8"]
    }
  }

  # Cloud-init mutates fields after first boot. Proxmox
  # regenerates MAC on clone. Ignoring stops false drift.
  lifecycle {
    ignore_changes = [
      network_device,
    ]
  }
}

# =======================================================================
# === Web Server 1 ======================================================
# =======================================================================

resource "proxmox_virtual_environment_vm" "web_01" {
  name        = "web-01${local.env.name_suffix}"
  node_name   = var.proxmox_node_name
  vm_id       = local.env.vm_base + 20
  description = "Iteration 2 web server (Nginx)"

  agent { enabled = false }

  clone {
    vm_id = var.template_vm_id
    full  = true
  }

  cpu { cores = 2 }
  memory { dedicated = 1024 }

  network_device {
    bridge = "vmbr0"
    model  = "virtio"
  }

  initialization {
    ip_config {
      ipv4 {
        address = "192.168.50.${local.env.ip_base + 20}/24"
        gateway = "192.168.50.1"
      }
    }
    user_account {
      username = "admin"
      keys     = local.vm_admin_public_keys
    }
  }

  lifecycle {
    ignore_changes = [network_device, initialization[0].user_account]
  }
}

# =======================================================================
# === Database Server 1 =================================================
# =======================================================================

resource "proxmox_virtual_environment_vm" "db_01" {
  name        = "db-01${local.env.name_suffix}"
  node_name   = var.proxmox_node_name
  vm_id       = local.env.vm_base + 30
  description = "Iteration 2 database server (PostgreSQL 16)"

  agent { enabled = false }

  clone {
    vm_id = var.template_vm_id
    full  = true
  }

  cpu { cores = 2 }
  memory { dedicated = 1024 }

  disk {
    datastore_id = "local-lvm"
    interface    = "scsi0"
    size         = 20
  }

  network_device {
    bridge = "vmbr0"
    model  = "virtio"
  }

  initialization {
    ip_config {
      ipv4 {
        address = "192.168.50.${local.env.ip_base + 30}/24"
        gateway = "192.168.50.1"
      }
    }
    user_account {
      username = "admin"
      keys     = local.vm_admin_public_keys
    }
  }

  lifecycle {
    ignore_changes = [network_device, initialization[0].user_account]
  }
}
