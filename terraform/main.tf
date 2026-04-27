# Resources. Defines the actual VMs Terraform creates on Proxmox.

resource "proxmox_virtual_environment_vm" "control_node" {
  name      = "control-node"
  node_name = var.proxmox_node_name
  vm_id     = 511

  # qemu-guest-agent is not installed in template 9000, so the
  # plugin must not wait for it to respond. Ansible's common role
  # installs the agent in iteration 2.
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

  memory {
    dedicated = 2048
  }

  network_device {
    bridge = "vmbr0"
    model  = "virtio"
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
      keys     = local.vm_admin_public_keys
    }
  }

  # Cloud-init mutates user_account fields after first boot, and
  # Proxmox regenerates the network MAC on clone. Ignoring these
  # changes prevents Terraform from "fixing" them on every run.
  lifecycle {
    ignore_changes = [
      network_device,
      initialization[0].user_account,
    ]
  }
}