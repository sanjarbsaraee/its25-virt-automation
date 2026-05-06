# Packer automates Debian 12 template builds (ID 9001).
# Every project VM clones from this template. Without it,
# installs are manual — 10+ min each, risk of drift.

packer {
  required_plugins {
    proxmox = {
      version = ">= 1.1.3"
      source  = "github.com/hashicorp/proxmox"
    }
  }
}

# Packer reads PKR_VAR_* environment variables injected
# by Infisical CLI: infisical run -- packer build .
variable "proxmox_token" {
  type      = string
  sensitive = true
}

variable "ssh_password" {
  type      = string
  sensitive = true
}

source "proxmox-iso" "debian-12-gold" {
  # Localhost because Packer runs on the Proxmox host.
  proxmox_url              = "https://127.0.0.1:8006/api2/json"
  username                 = "terraform@pve!terraform-token"
  token                    = var.proxmox_token
  node                     = "pve"
  # Self-signed cert on Proxmox, so TLS check is skipped.
  insecure_skip_tls_verify = true
  # Guest agent lets Proxmox read VM IP and state.
  qemu_agent               = true

  vm_id                = 9001
  vm_name              = "debian-12-gold"
  template_description = "Debian 12 Gold Template (Swedish Locale)"

  cores  = 1
  memory = 1024

  network_adapters {
    bridge = "vmbr0"
    model  = "virtio"
  }

  disks {
    disk_size    = "20G"
    storage_pool = "local-lvm"
    type         = "scsi"
  }

  boot_iso {
    type     = "ide"
    iso_file = "local:iso/debian-12.9.0-amd64-netinst.iso"
    unmount  = true
  }

  # Simulates keystrokes in the VM console to start install.
  # preseed.cfg serves via host bridge IP, answers all prompts.
  boot_command = [
    "<esc><wait>",
    "install <wait>",
    " fb=false <wait>",
    " debian-installer/locale=en_US.UTF-8 <wait>",
    " console-setup/ask_detect=false <wait>",
    " keyboard-configuration/xkb-keymap=se <wait>",
    " auto=true <wait>",
    " priority=critical <wait>",
    " preseed/url=http://192.168.50.197:8000/preseed.cfg <wait>",
    "<enter>"
  ]
  boot_wait = "10s"

  # Packer SSHs in to confirm install finished.
  # Password from Infisical via PKR_VAR_ssh_password.
  ssh_username = "automation"
  ssh_password = var.ssh_password
  ssh_timeout  = "30m"
}

build {
  sources = ["source.proxmox-iso.debian-12-gold"]

  # Grants automation user passwordless sudo so Ansible
  # can escalate without interactive prompts.
  provisioner "shell" {
    inline = [
      "echo 'automation ALL=(ALL) NOPASSWD:ALL' | sudo tee /etc/sudoers.d/automation",
      "sudo chown -R automation:automation /home/automation"
    ]
  }

  # Cleans unique IDs before converting to template.
  # SSH host keys regenerate at clone boot, machine-id
  # reset gives each clone a unique DHCP lease.
  provisioner "shell" {
    inline = [
      "sudo apt-get clean",
      "sudo rm -f /etc/ssh/ssh_host_*",
      "sudo truncate -s 0 /etc/machine-id",
      "sudo truncate -s 0 /var/lib/dbus/machine-id"
    ]
  }
}