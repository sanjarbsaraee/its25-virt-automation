# Two filters that block traffic to each VM. One runs in
# the Proxmox host, the other inside the VM. If we
# misconfigure one, the other still protects.

# --- Per-VM activation ---
# The cluster-level switch at the bottom of this file is
# not enough. Each VM also needs its own switch.

resource "proxmox_virtual_environment_firewall_options" "vm" {
  for_each = local.vm_fleet

  node_name = var.proxmox_node_name
  vm_id     = proxmox_virtual_environment_vm.nodes[each.key].vm_id

  enabled = true

  # DROP blocks silently. REJECT bounces a refusal back,
  # which tells an attacker the host is there.
  input_policy  = "DROP"
  output_policy = "ACCEPT"
  log_level_in  = "info"
}

# --- Reusable rule packs ---
# These groups let many VMs share the same rules. Change
# the group, every VM that uses it gets the update.

# Lets us SSH in from two places, the office LAN and
# Tailscale. Tailscale needs its own rule since it uses a
# different IP range (100.64.0.0/10).
resource "proxmox_virtual_environment_cluster_firewall_security_group" "ssh_from_mgmt" {
  name    = "ssh-from-mgmt"
  comment = "SSH inbound from LAN and Tailscale"

  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = "22"
    source  = "${var.lan_subnet}.0/24"
    comment = "SSH from management LAN"
  }

  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = "22"
    source  = "100.64.0.0/10"
    comment = "SSH from Tailscale CGNAT"
  }
}

# Only lb-01 uses this group. The web servers should never
# answer HTTP requests from the public.
resource "proxmox_virtual_environment_cluster_firewall_security_group" "http_public" {
  name    = "http-public"
  comment = "HTTP inbound from anywhere"

  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = "80"
    comment = "HTTP public"
  }
}

# The load balancer must be the only way to reach the
# Flask app. This rule blocks anyone who tries to reach a
# web server directly.
resource "proxmox_virtual_environment_cluster_firewall_security_group" "flask_from_lb" {
  name    = "flask-from-lb"
  comment = "Flask port from lb-01"

  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = "8080"
    source  = "${var.lan_subnet}.${local.env.ip_base + 40}/32"
    comment = "Flask from lb-01"
  }
}

# Only the web servers should reach the database. Two
# rules because Proxmox accepts one sender address per rule.
resource "proxmox_virtual_environment_cluster_firewall_security_group" "pg_from_web" {
  name    = "pg-from-web"
  comment = "PostgreSQL from web tier"

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

# --- Per-VM rule bindings ---
# One firewall_rules resource per VM. The bpg provider
# does not allow more (issue #1492).

resource "proxmox_virtual_environment_firewall_rules" "vm_rules" {
  for_each = local.vm_fleet

  node_name = var.proxmox_node_name
  vm_id     = proxmox_virtual_environment_vm.nodes[each.key].vm_id

  # All VMs get this rule. The dynamic blocks below add
  # extra rules depending on the VM's role.
  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.ssh_from_mgmt.name
    comment        = "SSH baseline"
  }

  dynamic "rule" {
    for_each = each.value.role == "lb" ? [1] : []
    content {
      security_group = proxmox_virtual_environment_cluster_firewall_security_group.http_public.name
      comment        = "HTTP for lb-01"
    }
  }

  dynamic "rule" {
    for_each = each.value.role == "web" ? [1] : []
    content {
      security_group = proxmox_virtual_environment_cluster_firewall_security_group.flask_from_lb.name
      comment        = "Flask from lb-01"
    }
  }

  dynamic "rule" {
    for_each = each.value.role == "db" ? [1] : []
    content {
      security_group = proxmox_virtual_environment_cluster_firewall_security_group.pg_from_web.name
      comment        = "PostgreSQL from web"
    }
  }
}

# --- Datacenter activation ---
# Turns the firewall service on at the cluster level.
# Without this, every rule above is ignored.

resource "proxmox_virtual_environment_cluster_firewall" "datacenter" {
  enabled        = true
  input_policy   = "DROP"
  output_policy  = "ACCEPT"
  forward_policy = "ACCEPT"

  log_ratelimit {
    enabled = true
    burst   = 10
    rate    = "5/second"
  }

  # Waits for SSH rules to exist first. Otherwise the
  # apply turns on the firewall before SSH is allowed and locks us out mid-run.
  depends_on = [
    proxmox_virtual_environment_firewall_options.vm,
    proxmox_virtual_environment_firewall_rules.vm_rules,
  ]
}