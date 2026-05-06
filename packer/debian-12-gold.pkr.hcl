packer {
    required_plugins {
        proxmox = {
            version = ">= 1.1.3"
            source  = "github.com/hashicorp/proxmox"
        }
    }
}

source "proxmox-iso" "debian-12-gold" {
  proxmox_url = "https://127.0.0.1:8006/api2/json"
  username    = "jim@pam"
  password    = "HundAlpBoll24!"
  node        = "pve"
  insecure_skip_tls_verify = true
  qemu_agent               = true

  vm_id   = 9001
  vm_name = "debian-12-gold"
  template_description = "Debian 12 Gold Template (Swedish Locale)"

  # Hardware
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

  # ISO Configuration (Modern Way)
  boot_iso {
    type         = "ide"
    iso_file     = "local:iso/debian-12.9.0-amd64-netinst.iso"
    unmount      = true
  }

  # Preseed Configuration (Local Relay Method)
  # Using the bridge IP so the VM can reach the host
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

  # SSH (Used by Packer to check if the installation finished)
  ssh_username = "automation"
  ssh_password = "automation"
  ssh_timeout  = "30m"
}

build {
  sources = ["source.proxmox-iso.debian-12-gold"]

  # Step 1: Fix our home directory permissions (The "Foundation")
  provisioner "shell" {
    inline = [
      "echo 'automation ALL=(ALL) NOPASSWD:ALL' | sudo tee /etc/sudoers.d/automation",
      "sudo chown -R automation:automation /home/automation"
    ]
  }

  # Step 2: The "Industry Standard" Cleanup (The Purge)
  # This makes the image a true "Golden" template.
  provisioner "shell" {
    inline = [
      "sudo apt-get clean",
      "sudo rm -f /etc/ssh/ssh_host_*",
      "sudo truncate -s 0 /etc/machine-id",
      "sudo truncate -s 0 /var/lib/dbus/machine-id"
    ]
  }
}