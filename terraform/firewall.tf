# This file contains all Proxmox firewall configurations for Iteration 4.
# It implements defense-in-depth on a flat network.

# --- VM Firewall Options ---
# Enables the firewall on each VM and sets the default policy.
resource "proxmox_virtual_environment_firewall_options" "vm" {
  for_each = local.vm_fleet

  node_name = var.proxmox_node_name
  vm_id     = proxmox_virtual_environment_vm.nodes[each.key].vm_id

  enabled       = true
  input_policy  = "DROP"   # Default deny incoming
  output_policy = "ACCEPT" # Default allow outgoing
  log_level_in  = "info"
}

# --- Cluster Security Groups ---
# These are reusable rule sets defined at the datacenter level.

# Allows SSH access from the management subnet.
resource "proxmox_virtual_environment_cluster_firewall_security_group" "ssh_from_mgmt" {
  name    = "ssh-from-mgmt"
  comment = "Allow SSH from the management network"

  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = "22"
    source  = "${var.lan_subnet}.0/24"
    comment = "SSH from management"
  }

  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = "22"
    source  = "100.64.0.0/10"
    comment = "SSH from Tailscale"
  }
}

# Allows public HTTP access (port 80) to the load balancer.
resource "proxmox_virtual_environment_cluster_firewall_security_group" "http_public" {
  name    = "http-public"
  comment = "Allow public HTTP/HTTPS access"

  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = "80"
    comment = "HTTP"
  }

  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = "80"
    source  = "100.64.0.0/10"
    comment = "Tailscale HTTP"
  }
}

# Allows traffic to the Flask app (port 8080) only from the Load Balancer.
resource "proxmox_virtual_environment_cluster_firewall_security_group" "flask_from_lb" {
  name    = "flask-from-lb"
  comment = "Allow Flask port from LB"

  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = "8080"
    source  = "${var.lan_subnet}.${local.env.ip_base + 40}/32"
    comment = "Flask from lb-01"
  }
}

# Allows database access (port 5432) only from the web servers.
resource "proxmox_virtual_environment_cluster_firewall_security_group" "pg_from_web" {
  name    = "pg-from-web"
  comment = "Allow PostgreSQL from web tier"

  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = "5432"
    source  = "${var.lan_subnet}.${local.env.ip_base + 20}/32"
    comment = "Postgres from web-01"
  }

  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = "5432"
    source  = "${var.lan_subnet}.${local.env.ip_base + 21}/32"
    comment = "Postgres from web-02"
  }
}

# --- VM Firewall Rules Assignment ---
# Binds the security groups to specific VMs.

# Assigns both baseline SSH and role-specific rules to each VM.
# We must use a single firewall_rules resource per VM in the proxmox provider.
resource "proxmox_virtual_environment_firewall_rules" "vm_rules" {
  for_each = local.vm_fleet

  node_name = var.proxmox_node_name
  vm_id     = proxmox_virtual_environment_vm.nodes[each.key].vm_id

  # Force replacement of any orphaned rules from the previously failed apply
  # overwrite = true

  # All VMs get the SSH baseline rule
  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.ssh_from_mgmt.name
    comment        = "SSH baseline"
  }

  # Load Balancer gets public HTTP access
  dynamic "rule" {
    for_each = each.value.role == "lb" ? [1] : []
    content {
      security_group = proxmox_virtual_environment_cluster_firewall_security_group.http_public.name
    }
  }

  # Web servers get Flask access from LB
  dynamic "rule" {
    for_each = each.value.role == "web" ? [1] : []
    content {
      security_group = proxmox_virtual_environment_cluster_firewall_security_group.flask_from_lb.name
    }
  }

  # Database server gets Postgres access from Web servers
  dynamic "rule" {
    for_each = each.value.role == "db" ? [1] : []
    content {
      security_group = proxmox_virtual_environment_cluster_firewall_security_group.pg_from_web.name
    }
  }
}
