# Architecture Decision Records

This file records the design choices that shaped the project. Each entry
follows the standard ADR template: context, decision, consequences. The
list is chronological. Decisions reference each other where they
connect.

For the current state of the infrastructure, see the [README](../../README.md).
For lessons learned during the build, see [RETROSPECTIVE](RETROSPECTIVE.md).

---

## ADR-001: Control node on the LAN, not behind NAT

**Status:** Accepted (2026-04-19)

**Context.** The original plan put the Ansible control node on an
internal virtual network (`192.168.56.10`) behind a NAT VM. The idea
was to mirror a typical office layout where management hosts live on a
separate segment. In practice this meant the control node needed a
second VM (the NAT host) to reach DNS and apt repositories, and
cloud-init had to bootstrap through that hop.

**Decision.** Place the control node directly on the LAN bridge
`vmbr0` at `192.168.50.10`. No NAT.

**Consequences.** Cloud-init reaches DNS and apt repos in one hop.
First-boot bootstrap finishes in 90 seconds instead of waiting for a
second VM to come up. The trade-off is that the control node sits on
the same broadcast domain as the workload VMs. The Proxmox firewall
plus per-VM UFW (see ADR-003) compensates for that by restricting
which ports the control node exposes.

---

## ADR-002: Debian 12 over Ubuntu 24.04 for the golden image

**Status:** Accepted (2026-04-22)

**Context.** Both distributions are viable bases for Proxmox VMs. The
original plan called for Ubuntu Server 24.04 because the team was more
familiar with it from previous courses. Two concerns surfaced during
the Packer setup: Debian 12 matches the Proxmox host's own base OS,
and a minimal Debian 12 install has a smaller memory footprint than
Ubuntu 24.04 (about 60 MB lower idle), which matters on a 16 GB host
running six VMs.

**Decision.** Build the golden image (Packer template `9001`) from
Debian 12.

**Consequences.** Lower idle RAM frees up headroom for the monitoring
stack added in iteration 5. Package versions track Debian-stable rather
than Ubuntu-rolling. Long-term support runs through July 2028 with
LTS extending further. The team had to learn the Debian package layout
in two places (apt sources format, kernel naming).

---

## ADR-003: Two firewall layers instead of a dedicated firewall VM

**Status:** Accepted (2026-05-10)

**Context.** The original network plan called for VLAN segmentation
and a dedicated `firewall-01` VM running nftables to route between
segments. This pattern is common in office networks but adds
considerable complexity: a routing VM is one more thing to provision,
secure, and patch, and VLANs require Proxmox bridge configuration that
is hard to automate cleanly with Terraform.

**Decision.** Skip VLANs and `firewall-01`. Apply two filter layers
instead:

1. The Proxmox cluster firewall (defined in `terraform/firewall.tf`)
   filters at the hypervisor level before packets reach a VM.
2. UFW inside each VM (configured by Ansible roles) filters again at
   the OS level.

**Consequences.** A misconfiguration in one layer does not expose the
VM, because the other still blocks the traffic. Less code (no VLANs
to provision), less RAM (no firewall VM), simpler defense to explain.
The trade-off is that all VMs share one broadcast domain, so we rely
on the firewall rules rather than layer-2 isolation. For a six-VM lab
this works; a 100-VM environment would tip back toward VLANs.

---

## ADR-004: Prometheus + Grafana stack over Wazuh + Loki

**Status:** Accepted (2026-05-10)

**Context.** Iteration 5 originally targeted a SIEM-style stack with
Wazuh as the security monitoring core and Loki + Promtail for log
aggregation. The combined memory footprint (Wazuh manager ~3 GB,
indexer ~1 GB, Loki ~600 MB) plus agents on every VM would consume
about 5 GB of the 16 GB host budget, leaving little headroom for the
six application VMs.

**Decision.** Replace the SIEM stack with Prometheus + Grafana +
Alertmanager for metrics-based monitoring, and add `pgaudit` +
`pg_stat_statements` for database-level auditing. Keep logs local on
each VM, accessed over SSH when needed.

**Consequences.** Total monitoring footprint dropped to about 1.5 GB
(monitor-01 with 2 GB allocation). The team trades centralized log
search for query-level database auditing and rich metrics dashboards.
Log aggregation can come back as iteration 6 if the project scales.

---

## ADR-005: Kubernetes out of scope

**Status:** Accepted (2026-05-12)

**Context.** A K3s deployment was considered as an extension to
demonstrate container orchestration on top of the existing fleet.
Three options were evaluated: full K3s cluster on the existing VMs,
single-node K3s as a stretch goal, or skip entirely.

**Decision.** Skip K3s. The existing VM-based architecture already
covers the design goals the project set out to demonstrate
(reproducibility, layered security, observability, redundancy at the
web tier). Adding container orchestration would mean defending two
orchestration models in parallel.

**Consequences.** Less to maintain and less to explain. The team can
return to containers in a future iteration if a use case appears that
VMs do not handle well. No container-aware tooling needed for now.

---

## ADR-006: Tailscale subnet routing moved from host to dedicated LXC

**Status:** Accepted (2026-05-14, superseded the original host-based
setup from 2026-05-11)

**Context.** Subnet routing initially ran on the Proxmox host itself,
which advertised `192.168.50.0/24` to the tailnet so operators could
reach VMs directly. Two days into production use, short-lived HTTP
flows from laptops to VMs started failing silently while SSH
continued to work. Investigation showed that the host's own firewall
and Tailscale's stateful filter held independent connection-tracking
tables. Returns matched the host's conntrack but not Tailscale's, so
Tailscale dropped them.

**Decision.** Build a dedicated `tailscale-gw` LXC container at
`192.168.50.5` and move the subnet router role there. The host stays
on the tailnet for administrative SSH but no longer advertises
routes. Build steps are documented in
[`tailscale-gw-lxc.md`](../setup/tailscale-gw-lxc.md).

**Consequences.** Conntrack conflict eliminated because the container
runs no other firewall. The hypervisor is isolated from
subnet-routing traffic, reducing its attack surface. The trade-off is
one more managed component (256 MB RAM and a separate VM to maintain).

---

## ADR-007: Workspace-prefixed cluster security group names

**Status:** Accepted (2026-05-14)

**Context.** Each team member runs a development workspace alongside
the main environment. VM IDs and IP addresses already use a numeric
offset per workspace (+100 for Sanjar, +200 for Jim) to avoid
collisions. Proxmox cluster security groups, however, live in a
global namespace at the cluster level. When two workspaces applied
the same group name (`flask-from-lb`), the last `terraform apply`
silently overwrote the rules from the earlier one.

**Decision.** Suffix role-specific security group names with the
workspace identifier: `flask-from-lb-sanjar`, `flask-from-lb-jim`,
and `flask-from-lb` for the main workspace. Groups whose rules are
identical across environments (`ssh-from-mgmt`, `http-public`) stay
without a suffix.

**Consequences.** All three workspaces can apply against the same
host without overwriting each other. Group names cap at the
Proxmox-imposed 18-character limit, which forced shorter base names
(`pg-from-mon` instead of `pg-from-monitor`). The mapping lives in
`terraform/firewall.tf` and is regenerated per workspace through
`${local.env.name_suffix}`.
