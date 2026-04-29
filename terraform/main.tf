# Resources. Defines what Terraform creates on the Proxmox host.

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
  # Workspace-aware naming. Default workspace builds production
  # control-node. Dev workspaces append the workspace name so
  # parallel dev VMs do not collide with each other or main.
  name      = terraform.workspace == "its25-virt-automation" ? "control-node" : "control-node-${terraform.workspace}"
  node_name = var.proxmox_node_name
 
  # Workspace-aware vm_id. Main workspace owns 510. Sanjar's
  # dev maps to 521, Jim's to 522. Hard-coded mapping until
  # iter 2 needs more entries.
  vm_id = lookup({
    "its25-virt-automation" = 510
    "its25-sanjar-dev" = 521
    "its25-jim-dev" = 522
  }, terraform.workspace, 510)

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
        # Workspace-aware IP. Main owns 192.168.50.10. Dev
        # workspaces use .21 and .22. Parallel dev VMs need
        # unique IPs so they do not collide on the LAN.
        address = lookup({
          "its25-virt-automation"   = "192.168.50.10/24"
          "its25-sanjar-dev"        = "192.168.50.21/24"
          "its25-jim-dev"           = "192.168.50.22/24"
        }, terraform.workspace, "192.168.50.10/24")
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