# Defense in depth. Two firewalls per VM — one on the
# Proxmox host, one inside. A mistake in one still gets
# blocked by the other.

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

# Two ways in via SSH: the office LAN and Tailscale.
# Tailscale lives in 100.64.0.0/10 and needs its own rule.
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

# Web servers only answer through lb-01. Direct access
# from anywhere else stays blocked.
resource "proxmox_virtual_environment_cluster_firewall_security_group" "flask_from_lb" {
  name    = "flask-from-lb"
  comment = "Flask port from lb-01"

  rule {
    enabled = true
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
    enabled = true
    type    = "in"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = "5432"
    source  = "${var.lan_subnet}.${local.env.ip_base + 20}/32"
    comment = "Postgres from web-01"
  }

  rule {
    enabled = true
    type    = "in"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = "5432"
    source  = "${var.lan_subnet}.${local.env.ip_base + 21}/32"
    comment = "Postgres from web-02"
  }
}

# Lets the postgres exporter on monitor-01 read database
# stats. Other hosts cannot reach 5432 on db-01.
resource "proxmox_virtual_environment_cluster_firewall_security_group" "pg_from_monitor" {
  name    = "pg-from-monitor"
  comment = "PostgreSQL from monitor-01"

  rule {
    enabled = true
    type    = "in"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = "5432"
    source  = "${var.lan_subnet}.${local.env.ip_base + 50}/32"
    comment = "Postgres from monitor-01"
  }
}

# Prometheus on monitor-01 reads metrics from every VM
# on port 9100. Only monitor-01's IP is allowed in.
resource "proxmox_virtual_environment_cluster_firewall_security_group" "node_exp_from_mon" {
  name    = "node-exp-from-mon"
  comment = "Node exporter metrics from monitor-01"

  rule {
    enabled = true
    type    = "in"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = "9100"
    source  = "${var.lan_subnet}.${local.env.ip_base + 50}/32"
    comment = "Metrics from monitor-01"
  }
}

# Grafana runs on monitor-01:3000 but users reach it via
# lb-01/grafana. Only lb-01 is allowed in on the back end.
resource "proxmox_virtual_environment_cluster_firewall_security_group" "grafana_from_lb" {
  name    = "grafana-from-lb"
  comment = "Grafana port from lb-01"

  rule {
    enabled = true
    type    = "in"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = "3000"
    source  = "${var.lan_subnet}.${local.env.ip_base + 40}/32"
    comment = "Grafana from lb-01"
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

  # All VMs accept metrics scraping from monitor-01.
  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.node_exp_from_mon.name
    comment        = "Node exporter metrics"
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

  dynamic "rule" {
    for_each = each.value.role == "db" ? [1] : []
    content {
      security_group = proxmox_virtual_environment_cluster_firewall_security_group.pg_from_monitor.name
      comment        = "PostgreSQL from monitor-01"
    }
  }

  dynamic "rule" {
    for_each = each.value.role == "monitor" ? [1] : []
    content {
      security_group = proxmox_virtual_environment_cluster_firewall_security_group.grafana_from_lb.name
      comment        = "Grafana from lb-01"
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

  # Without this, the firewall switches on before SSH is
  # allowed and locks us out mid-apply.
  depends_on = [
    proxmox_virtual_environment_firewall_options.vm,
    proxmox_virtual_environment_firewall_rules.vm_rules,
  ]
}