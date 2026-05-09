# VMs and supporting resources on the Proxmox host.

locals {
  env_config = {
    "its25-virt-automation" = { name_suffix = "", vm_base = 500, ip_base = 0 }
    "its25-sanjar-dev"      = { name_suffix = "-sanjar", vm_base = 600, ip_base = 100 }
    "its25-jim-dev"         = { name_suffix = "-jim", vm_base = 700, ip_base = 200 }
  }

  env = lookup(local.env_config, terraform.workspace, local.env_config["its25-virt-automation"])

  # One entry per VM. Adding a new machine means one line here.
  vm_fleet = {
    "control-node" = { role = "control", ip_offset = 10, cores = 2, memory = 2048, disk_size = 20, desc = "Ansible Control Node" }
    "web-01"       = { role = "web", ip_offset = 20, cores = 2, memory = 1024, disk_size = 20, desc = "Nginx Web Server" }
    "db-01"        = { role = "db", ip_offset = 30, cores = 2, memory = 1024, disk_size = 40, desc = "PostgreSQL DB" }
  }

  # Ansible needs VM names and IPs. This builds that list
  # from vm_fleet so bootstrap can write it at first boot.
  inventory = {
    all = {
      children = {
        for role in distinct([for v in local.vm_fleet : v.role]) : role => {
          hosts = {
            for k, v in local.vm_fleet : "${k}${local.env.name_suffix}" => {
              ansible_host       = "${var.lan_subnet}.${local.env.ip_base + v.ip_offset}"
              ansible_connection = v.role == "control" ? "local" : null
            } if v.role == role
          }
        }
      }
    }
  }
}

# Cloud-init files uploaded to Proxmox via SSH.
resource "proxmox_virtual_environment_file" "ansible_bootstrap" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = var.proxmox_node_name
  source_raw {
    data = templatefile("${path.module}/ansible-bootstrap.yaml", {
      sanjar_key             = local.sanjar_key,
      jim_key                = local.jim_key,
      automation_key         = local.automation_key,
      hostname               = "control-node${local.env.name_suffix}",
      inventory_content      = yamlencode(local.inventory),
      automation_private_key = local.automation_private_key,
      db_password            = local.db_password
    })
    file_name = "ansible-bootstrap.yaml"
  }
}

resource "proxmox_virtual_environment_file" "vm_metadata" {
  for_each     = local.vm_fleet
  content_type = "snippets"
  datastore_id = "local"
  node_name    = var.proxmox_node_name
  source_raw {
    data = yamlencode({
      "instance-id"    = "${each.key}${local.env.name_suffix}"
      "local-hostname" = "${each.key}${local.env.name_suffix}"
    })
    file_name = "metadata-${each.key}${local.env.name_suffix}.yaml"
  }
}

# Creates all VMs from the vm_fleet map above.
resource "proxmox_virtual_environment_vm" "nodes" {
  for_each    = local.vm_fleet
  name        = "${each.key}${local.env.name_suffix}"
  node_name   = var.proxmox_node_name
  vm_id       = local.env.vm_base + each.value.ip_offset
  description = each.value.desc

  agent { enabled = true }
  clone {
    vm_id = var.template_vm_id
    full  = true
  }

  cpu { cores = each.value.cores }
  memory { dedicated = each.value.memory }

  disk {
    datastore_id = "local-lvm"
    interface    = "scsi0"
    size         = each.value.disk_size
  }

  network_device {
    bridge = var.lan_bridge
    model  = "virtio"
  }

  initialization {
    datastore_id = "local-lvm"

    # Control-node gets Ansible bootstrap, other VMs get
    # only a hostname via metadata.
    user_data_file_id = each.value.role == "control" ? proxmox_virtual_environment_file.ansible_bootstrap.id : null
    meta_data_file_id = each.value.role != "control" ? proxmox_virtual_environment_file.vm_metadata[each.key].id : null

    ip_config {
      ipv4 {
        address = "${var.lan_subnet}.${local.env.ip_base + each.value.ip_offset}/24"
        gateway = var.lan_gateway
      }
    }

    # Tailscale on the host hijacks DNS with 100.100.100.100.
    # Public servers bypass that so cloud-init can reach the internet.
    dns {
      servers = ["1.1.1.1", "8.8.8.8"]
    }

    user_account {
      username = "automation"
      keys     = local.vm_admin_public_keys
    }
  }

  lifecycle {
    ignore_changes = [
      network_device,
      initialization[0].user_account,
      cpu[0].flags
    ]
  }
}
