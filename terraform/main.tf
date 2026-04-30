# Resources. Defines what Terraform creates on the Proxmox host.

# "env_config" maps each workspace to a base for VM IDs and IPs.
# Main owns 510-series. Dev workspaces shift both ranges so
# parallel VMs do not collide on the host or LAN.
locals {
  env_config = {
    "its25-virt-automation" = { name_suffix = "",        vm_base = 500, ip_base = 0 }
    "its25-sanjar-dev"      = { name_suffix = "-sanjar", vm_base = 600, ip_base = 100 }
    "its25-jim-dev"         = { name_suffix = "-jim",    vm_base = 700, ip_base = 200 }
  }

  # "lookup" returns the entry for the active workspace. It
  # falls back to the main config if the name is unknown, so
  # an unset workspace cannot accidentally collide with main.
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

# Control-node VM. Cloned from template 9000 and configured
# from the ansible_bootstrap snippet on first boot.
resource "proxmox_virtual_environment_vm" "control_node" {
  # Name suffix tags the owner. Main is "", dev workspaces
  # append "-sanjar" or "-jim".
  name      = "control-node${local.env.name_suffix}"
  node_name = var.proxmox_node_name

  # vm_id is base + 10. Main 510, Sanjar 610, Jim 710.
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
    bridge = var.lan_bridge

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
        # Last octet is ip_base + 10. Main .10, Sanjar .110,
        # Jim .210.
        address = "${var.lan_subnet}.${local.env.ip_base + 10}/24"
        gateway = var.lan_gateway
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

# Web-01 VM for iter 2. Hosts Nginx behind the load balancer.
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

  # Memory in MiB. 1024 fits Nginx plus a small static site.
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

    # "user_account" injects SSH keys into the cloud-init default
    # user. The control_node uses ansible_bootstrap.yaml instead.
    # Iter 2 VMs use this simpler form because they have no
    # snippet yet.
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

# Db-01 VM for iter 2. Hosts PostgreSQL 16.
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

  # Memory in MiB. 1024 covers PostgreSQL with a small dataset.
  memory {
    dedicated = 1024
  }

  # Extra disk for database storage. 20 GiB on local-lvm.
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