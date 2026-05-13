# its25-virt-automation

Automated infrastructure on Proxmox VE. Terraform provisions VMs, Ansible
configures them, Prometheus and Grafana monitor them, and Infisical stores
secrets. Capstone project for the Virtualization Technology and Automation
course (ITS25) at Yrkeshögskolan i Enköping.

---

## Table of contents

- [Architecture](#architecture)
- [VMs and IP addresses](#vms-and-ip-addresses)
- [Repository structure](#repository-structure)
- [Components](#components)
- [Prerequisites](#prerequisites)
- [Getting started](#getting-started)
- [Secrets](#secrets)
- [Security measures](#security-measures)
- [Security analysis](#security-analysis)
- [Verification](#verification)
- [Design choices](#design-choices)
- [Iterations](#iterations)
- [Team](#team)

---

## Architecture

```
    Operator laptops (Windows, PowerShell + Git Bash)
              |
              |  Tailscale (WireGuard tunnel, no open ports)
              |
      Proxmox VE host (GEEKOM A5, 16 GB RAM)
              |
              +-- HCP Terraform agent (runs plans and applies)
              |
   +----------+----------+----------+----------+----------+
   |          |          |          |          |          |
control-node lb-01    web-01    web-02     db-01    monitor-01
 (Ansible)   (Nginx LB) (Flask)  (Flask)  (PostgreSQL) (Prometheus+
                                          (pgaudit)    Grafana)
```

We work from Windows laptops. Tailscale gives us access to the Proxmox host
without exposing its management port to the internet. The HCP Terraform
agent runs on the host because HCP's cloud runners cannot reach the
Tailscale network.

Each iteration deploys in two commands:

1. `terraform apply` from a laptop provisions or updates VMs.
2. SSH into the control-node and run `ansible-playbook playbooks/site.yml`.

Cloud-init installs Ansible, Git, and Python on the control-node at first
boot, clones this repo, and installs Galaxy collections. Step 2 works
immediately without manual setup.

---

## VMs and IP addresses

Each HCP Terraform workspace (main, sanjar-dev, jim-dev) shifts VM IDs and
IPs so parallel environments never collide. The table below shows the main
workspace. Dev workspaces add an offset of 100 (Sanjar) or 200 (Jim) to the
base IP.

| VM | Role | IP address | Iteration | Description |
|---|---|---|---|---|
| `control-node` | Ansible controller | 192.168.50.10 | 1 | Runs playbooks against all other VMs |
| `web-01` | Web server | 192.168.50.20 | 2 | Flask + Gunicorn, serves the application |
| `web-02` | Web server | 192.168.50.21 | 3 | Second backend behind the load balancer |
| `db-01` | Database server | 192.168.50.30 | 2 | PostgreSQL 16, TLS, pgaudit |
| `lb-01` | Load balancer | 192.168.50.40 | 3 | Nginx, round-robin to web-01 and web-02 |
| `monitor-01` | Monitoring server | 192.168.50.50 | 5 | Prometheus, Grafana, Alertmanager, postgres_exporter |

---

## Repository structure

```
.
├── terraform/
│   ├── terraform.tf              # Backend (HCP) and required providers
│   ├── providers.tf              # Connects to Infisical and Proxmox
│   ├── variables.tf              # Input variables with defaults
│   ├── data.tf                   # Pulls secrets from Infisical
│   ├── main.tf                   # VM fleet via for_each loop
│   ├── firewall.tf               # Proxmox firewall: security groups, VM rules
│   ├── outputs.tf                # IPs and VM IDs for Ansible
│   └── ansible-bootstrap.yaml    # Cloud-init template for control-node
│
├── ansible/
│   ├── ansible.cfg               # Paths, output format, SSH pipelining
│   ├── inventories/prod/
│   │   ├── proxmox.yml           # Dynamic inventory (community.proxmox.proxmox)
│   │   └── group_vars/
│   │       └── all/vars.yml      # Shared variables, Infisical lookups
│   ├── playbooks/
│   │   └── site.yml              # Orchestrator, one play per group
│   ├── roles/
│   │   ├── control_node_check/   # Verifies packages and connectivity
│   │   ├── common/               # Baseline packages, timezone, UFW, node_exporter
│   │   ├── flask_app/            # Flask + Gunicorn as systemd service
│   │   ├── postgres_server/      # PostgreSQL 16, TLS, pgaudit, pg_stat_statements
│   │   ├── nginx_lb/             # Nginx as round-robin LB, /grafana subpath
│   │   └── prometheus_server/    # Prometheus, Grafana, Alertmanager, postgres_exporter
│   └── collections/
│       └── requirements.yml      # Galaxy collections
│
├── packer/
│   ├── debian-12-gold.pkr.hcl    # Builds the golden template (ID 9001)
│   └── http/
│       └── preseed.cfg           # Unattended Debian 12 install config
│
├── scripts/
│   ├── verify-iter1.sh           # 11 checks for the foundation
│   ├── verify-iter2.sh           # 14 checks for web, db, TLS, firewall
│   ├── verify-iter3.sh           # 11 checks for LB, redundancy, end-to-end
│   ├── verify-iter4.sh           # 24 checks for firewall and SSH hardening
│   ├── verify-iter5.sh           # 26 checks for monitoring, pgaudit, exporters
│   └── verify-node.sh            # General health check for any VM
│
├── docs/                         # Setup guides and design records
└── .gitignore
```

Terraform follows HashiCorp's standard module structure. Ansible roles live
under `ansible/roles/`, one directory per role. Packer builds the golden
template that all VMs clone from. New roles arrive with each iteration.

---

## Components

### Terraform

Provisions VMs on Proxmox using the `bpg/proxmox` provider. Each VM clones
from a Debian 12 golden template (VM ID 9001) built by Packer. The
`main.tf` file uses a single `for_each` loop over a `vm_fleet` map, so
adding a new VM means adding one line. A workspace-aware mapping assigns
unique VM IDs and IP addresses per environment, so dev VMs never interfere
with each other or with main.

### Ansible

Configures VMs after they boot. Playbooks run from the control-node, not
from our laptops. The `site.yml` file maps each host group to its roles.

Roles:

- `control_node_check` verifies packages and connectivity
- `common` installs baseline packages, sets the timezone, enables UFW
  with default-deny, and installs `node_exporter`
- `flask_app` deploys Flask behind Gunicorn as a systemd service
- `postgres_server` installs PostgreSQL 16 with TLS, enables `pgaudit`
  for DDL and WRITE logging, and creates the `exporter` read-only user
- `nginx_lb` configures Nginx as a round-robin load balancer and proxies
  `/grafana` to monitor-01:3000
- `prometheus_server` installs Prometheus, Alertmanager, Grafana, and
  `postgres_exporter`, then provisions Prometheus as the default Grafana
  data source

Database passwords come from Infisical at runtime via the `infisical.vault`
collection. No secrets touch the disk on the control-node.

Since iteration 3, Ansible uses dynamic inventory via the
`community.proxmox.proxmox` plugin instead of a static `hosts.yml`. The
plugin queries the Proxmox API at every invocation and filters VMs by
workspace suffix, so the three workspaces stay isolated on the same host.

### Packer

Automates the creation of the golden template (ID 9001). Without it,
template builds take 10+ minutes per install with risk of inconsistency
between VMs. The preseed file answers every Debian installer prompt
automatically. Packer credentials live in Infisical and inject at runtime
via the Infisical CLI:

```bash
infisical run -- packer build .
```

### Infisical

Stores the Proxmox API token, the SSH private key for the Terraform bot,
Packer credentials, the database password, the exporter password, and our
public SSH keys. Terraform reads these at apply time through the
`infisical` provider. Nothing secret lives in the repo or on local disk.

### HCP Terraform

Stores Terraform state remotely so we both work against the same state
file. Three workspaces (main, sanjar-dev, jim-dev) share the same
Infisical secrets. A self-hosted agent on the Proxmox host executes plans
and applies, since HCP's cloud runners cannot reach our Tailscale network.

### Cloud-init

A YAML snippet (`ansible-bootstrap.yaml`) that Proxmox passes to the
control-node at first boot. Cloud-init creates the `automation` user,
installs packages, clones this repo, writes the Infisical credentials
to `/etc/environment`, and installs Galaxy collections. This setup makes
the two-command flow possible.

### Firewall

Two filter layers block traffic to each VM. Proxmox firewall runs on the
host and filters before the packet reaches the VM. UFW runs inside each
VM and filters again. A bug in either layer does not expose the VM.

Proxmox rules live in `terraform/firewall.tf` as reusable cluster security
groups (`ssh-from-mgmt`, `http-public`, `flask-from-lb`, `pg-from-web`,
`pg-from-monitor`, `node-exp-from-mon`, `grafana-from-lb`). Each VM binds
the groups its role needs through a single `firewall_rules` resource.
UFW rules live in the Ansible roles: a baseline in `common` (default-deny
incoming, rate-limited SSH from LAN and Tailscale) and role-specific
allows in each component role.

SSH hardening uses the `devsec.hardening.ssh_hardening` role from Galaxy
with CIS-aligned defaults. Root login and password authentication are
disabled.

### Monitoring stack

Iteration 5 adds a dedicated monitoring VM (`monitor-01`) running four
services:

- **Prometheus** scrapes metrics from every VM every 15 seconds and
  stores them in a time-series database
- **Alertmanager** routes alerts produced by Prometheus rules
- **Grafana** displays the data in dashboards, reachable through
  `http://lb-01/grafana`
- **postgres_exporter** queries db-01 with the read-only `exporter` user
  and publishes database metrics

Every VM runs `node_exporter` on port 9100. The `pg-from-monitor` security
group allows monitor-01 to query db-01:5432 through the firewall. The
`grafana-from-lb` group restricts port 3000 to lb-01, so Grafana is
unreachable from anywhere else.

Database auditing on db-01 uses `pgaudit` configured to log DDL (schema
changes) and WRITE (INSERT, UPDATE, DELETE). The `pg_stat_statements`
extension tracks query performance for slow-query analysis. Logrotate
caps audit log size at 100 MB per file with daily rotation.

---

## Prerequisites

**On your Windows laptop:**

- [Terraform CLI](https://developer.hashicorp.com/terraform/install)
- [Git](https://git-scm.com/) (includes Git Bash)
- An SSH key pair for VM access
- Tailscale connected to the mesh network
- SSH config (`~/.ssh/config`) with host and VM blocks (see below)

**SSH config:**

The verify scripts and SSH commands rely on `~/.ssh/config` to find the
right key and user. Each team member needs this file on their laptop,
with their own key paths. ProxyJump routes through the Proxmox host so
VMs are reachable even outside the home LAN.

```
Host 100.94.227.10
  User <your-host-username>
  IdentityFile ~/.ssh/<your>_proxmox_key

Host 192.168.50.*
  ProxyJump <your-host-username>@100.94.227.10
  User automation
  IdentityFile ~/.ssh/<your>_vm_key
  StrictHostKeyChecking accept-new
  UserKnownHostsFile /dev/null
```

**Accounts:**

- HCP Terraform (organization: `its25-virt-automation`)
- Infisical (project secrets configured)

**On the Proxmox host:**

- Debian 12 golden template at VM ID 9001 (built by Packer)
- HCP Terraform agent running as a systemd service
- Tailscale connected

---

## Getting started

```bash
# 1. Clone the repo
git clone git@github.com:sanjarbsaraee/its25-virt-automation.git
cd its25-virt-automation/terraform

# 2. Initialize Terraform (connects to HCP backend)
terraform init

# 3. Provision VMs (33 resources, ~5 minutes)
terraform apply

# 4. Wait 2-3 minutes for cloud-init, then SSH into the control-node
ssh automation@192.168.50.10

# 5. Run the playbook
cd ~/its25-virt-automation/ansible
ansible-playbook -i inventories/prod/proxmox.yml playbooks/site.yml

# 6. Verify (from control-node, takes about 30 seconds)
cd ~/its25-virt-automation
bash scripts/verify-iter5.sh
```

After step 5, a second playbook run shows `changed=0`. The infrastructure
is idempotent.

After step 6, open `http://192.168.50.40/grafana` in a browser. Default
login is `admin / admin`; Grafana asks for a new password on first sign-in.
Prometheus is pre-configured as the default data source.

---

## Secrets

All secrets live in Infisical, never in the repo. Terraform reads them at
apply time through the `infisical` provider. Ansible reads them at
playbook time through the `infisical.vault` lookup. Packer reads its
secrets via the Infisical CLI.

| Secret | Purpose |
|---|---|
| `PROXMOX_API_TOKEN` | Authenticates Terraform against the Proxmox API |
| `TERRAFORM_BOT_PRIVATE_KEY` | SSH key the provider uses to upload cloud-init snippets |
| `SANJAR_VM_PUBLIC_KEY` | Sanjar's public key, injected into VMs |
| `JIM_VM_PUBLIC_KEY` | Jim's public key, injected into VMs |
| `AUTOMATION_PUBLIC_KEY` | Fleet SSH public key for control-node to worker |
| `AUTOMATION_PRIVATE_KEY` | Fleet SSH private key on control-node |
| `DB_PASSWORD` | PostgreSQL app_rw password, fetched by Ansible at runtime |
| `PG_EXPORTER_PASSWORD` | Read-only password for postgres_exporter (iter 5) |
| `INFISICAL_UNIVERSAL_AUTH_CLIENT_ID` | Machine identity for Ansible lookups (iter 5) |
| `INFISICAL_UNIVERSAL_AUTH_CLIENT_SECRET` | Paired secret for the client ID |
| `PKR_VAR_proxmox_token` | API key for Packer template builds |
| `PKR_VAR_ssh_password` | Password Packer uses to SSH in and verify install |

The Terraform secrets exist in all three HCP Terraform workspaces so each
environment provisions independently. The Packer secrets are used locally
via `infisical run`.

---

## Security measures

The project applies defense in depth across four layers:

| Layer | Measure | Verification |
|---|---|---|
| Network | Tailscale WireGuard tunnel, no open ports on Proxmox host | `tailscale status` from laptop |
| Host firewall | Proxmox cluster firewall with deny-by-default | `verify-iter4.sh` checks reachability |
| VM firewall | UFW on every VM with role-specific allow rules | `verify-iter4.sh` and `verify-iter5.sh` |
| SSH | `devsec.hardening.ssh_hardening`, root and password login disabled | `sshd -T` on each VM |
| Database | TLS-only connections, `pg_hba.conf` restricted to web tier | `verify-iter2.sh` rejects plaintext |
| Database | `pgaudit` logs DDL and WRITE with user, timestamp, SQL | `verify-iter5.sh` checks extension active |
| Database | `exporter` user has `pg_monitor` role only (read-only) | `verify-iter5.sh` checks role membership |
| Application | Flask runs as non-root `automation` user via Gunicorn | `ps aux \| grep gunicorn` |
| Secrets | All secrets in Infisical, never on disk or in repo | `git log --all -- terraform.tfvars` returns empty |
| Information | `server_tokens off` in Nginx hides version | `curl -I http://lb-01/` |

Iteration 4 added the firewall layers. Iteration 5 added the database
auditing, the read-only exporter role, and Infisical-based runtime secrets
for Ansible.

---

## Security analysis

### Known remaining risks

**Single point of failure: lb-01**

The load balancer has no redundant peer. If lb-01 crashes, no traffic
reaches the web tier.

*Mitigation path:* A second LB instance with keepalived (a tool that moves
a virtual IP between two machines on failure) or a managed cloud LB like
AWS ALB.

*Accepted because:* The host has 16 GB RAM total. A redundant LB plus
keepalived adds two more services per VM and requires a third public IP.
The trade-off is documented and defended in the oral presentation.

---

**Single point of failure: monitor-01**

If monitor-01 crashes, alerts stop firing and dashboards stop updating.
The metric data also disappears (no remote storage).

*Mitigation path:* Prometheus federation with a second instance, or remote
write to a managed time-series database (Grafana Cloud, Mimir, Thanos).

*Accepted because:* Loss of monitoring is not loss of service. The
application keeps serving traffic. Alerts can be reconfigured after a
rebuild in under 10 minutes.

---

**Grafana admin password defaults**

Grafana ships with `admin / admin` and prompts for a change at first
login. Until a human logs in, the default is active.

*Mitigation path:* Set `GF_SECURITY_ADMIN_PASSWORD` from Infisical at
install time, or disable the admin user entirely and use OAuth.

*Accepted because:* Grafana is only reachable through lb-01, which sits
behind the firewall and Tailscale. The attack surface is small and the
window is short.

---

**No centralized log aggregation**

Logs stay on each VM. Searching across the fleet requires SSH to every
host.

*Mitigation path:* Loki + Promtail (lightweight log shipper) on each VM,
shipping to monitor-01.

*Accepted because:* Six VMs are manageable individually. Loki adds another
500-800 MB RAM to monitor-01. Parked for iteration 6.

---

**Single SSH key for the `automation` account fleet-wide**

Every VM accepts the same `automation` key. Compromise of that key
compromises every host.

*Mitigation path:* Per-host keys with Ansible-Vault-stored mappings, or
short-lived certificates via SSH CA.

*Accepted because:* The key lives only in Infisical (Terraform reads it)
and on the control-node (encrypted disk, restricted access). Rotation is
a single Infisical update + playbook re-run.

### What protects the environment

Despite the risks above, the environment has the following defenses:

- Network segmentation: only lb-01 is reachable from outside; web and db
  tiers are behind the LAN
- Two-layer firewall (Proxmox + UFW), so a misconfiguration in one does
  not expose the VM
- Principle of least privilege: `exporter` user is read-only,
  `app_rw` cannot DDL, `automation` is the only privileged account
- All secrets in Infisical with audit logging
- pgaudit gives a complete audit trail of who changed what in the
  database
- Idempotent infrastructure: any drift is detected by running the
  playbook again and seeing non-zero `changed=` counts

---

## Verification

One verify script per iteration plus a generic node check. Scripts 1–4
run from a laptop and SSH into the target VMs. The iteration 5 script
runs on the control-node because it uses dynamic inventory and Infisical
credentials available only there.

**`verify-iter1.sh`** — 11 checks for the foundation:

```bash
bash scripts/verify-iter1.sh 192.168.50.10
```

| Category | What it checks |
|---|---|
| Connectivity | SSH login as `automation`, hostname set |
| Packages | Ansible, Git, Python 3 installed |
| Repository | Repo cloned, playbook and role exist |
| Galaxy | Infisical collection installed in `./collections` |
| Playbook | First run succeeds, second run is idempotent |

**`verify-iter2.sh`** — 14 checks for the web and database tiers:

```bash
bash scripts/verify-iter2.sh 192.168.50.20 192.168.50.30
```

| Category | What it checks |
|---|---|
| Flask | GET /, /health, /info, db_reachable |
| Process | Gunicorn runs as `automation`, service active |
| PostgreSQL | Version 16 running, TLS cert exists |
| TLS | TLS connection succeeds, plaintext rejected |
| Firewall | UFW active, port 5432 open from web tier |

**`verify-iter3.sh`** — 11 checks for load balancing and dynamic inventory:

```bash
bash scripts/verify-iter3.sh 192.168.50.40 192.168.50.20 192.168.50.21
```

| Category | What it checks |
|---|---|
| Nginx | Service running, listening on port 80 |
| Round-robin | Multiple requests hit different backends |
| Failover | Stopping a backend removes it from the pool |
| `server_tokens off` | HTTP response does not leak Nginx version |
| Idempotence | Re-running playbook shows `changed=0` |

**`verify-iter4.sh`** — 24 checks for firewall layers and SSH hardening:

```bash
bash scripts/verify-iter4.sh 192.168.50.10 192.168.50.20 192.168.50.21 192.168.50.30 192.168.50.40
```

| Category | What it checks |
|---|---|
| UFW status | Active and default-deny on every VM |
| SSH hardening | Root login disabled, password auth disabled |
| Allowed traffic | lb-01 reaches web-01:8080, web-01 reaches db-01:5432 |
| Blocked traffic | db-01 cannot reach web-01:8080, lb-01 cannot reach db-01:5432 |

**`verify-iter5.sh`** — 26 checks for monitoring, exporters, and pgaudit.
Run from the control-node:

```bash
cd ~/its25-virt-automation
bash scripts/verify-iter5.sh
```

| Category | What it checks |
|---|---|
| UFW | Active on every VM |
| Monitor services | Prometheus, Alertmanager, postgres_exporter, Grafana active |
| Listening ports | 9090, 3000, 9187 on monitor-01 |
| Prometheus health | `/-/healthy` returns 200, HighCpuUsage rule loaded |
| postgres_exporter | Publishes `pg_up` metric (database reachable) |
| node_exporter | Responds on every VM at :9100 |
| Grafana via lb-01 | `/grafana/api/health` returns `database: ok` |
| Database auditing | `pgaudit` and `pg_stat_statements` in shared_preload_libraries |
| Extensions | Both extensions CREATE'd in the `app` database |
| Database user | `exporter` user has `pg_monitor` role |

**`verify-node.sh`** — general health check for any VM:

```bash
bash scripts/verify-node.sh 192.168.50.10
```

The script detects whether the target is a control-node or a worker and
adjusts its checks. Useful for troubleshooting after a deploy.

---

## Design choices

### Why Proxmox instead of VirtualBox?

Proxmox is a type 1 hypervisor that runs directly on hardware. VirtualBox
is type 2 and runs on top of Windows. Proxmox gives us an environment
closer to production and lets us use Terraform with a real provider
instead of Vagrant. For a project targeting VG, this shows we can work
with the same tools used in production.

### Why Infisical instead of Ansible Vault?

Ansible Vault encrypts files at rest, but the decrypted values end up on
disk during a play. Infisical serves secrets over an API at the moment
Terraform or Ansible needs them. No secret file touches the repo or local
disk. Adding a new team member means granting Infisical access, not
distributing a shared vault password.

### Why a dedicated automation account?

A generic `admin` account for automation blurs the line between human and
machine access. The `automation` account is a dedicated service account
with passwordless sudo, used only by Ansible and cloud-init. Human
operators SSH in with their own named keys. This follows the principle of
least privilege and makes audit logs easier to read.

### Why a golden template with Packer?

Manual template installs take 10+ minutes per build and risk inconsistency
between VMs. Packer automates the process from a preseed file and produces
a bit-perfect image every time. The template includes `qemu-guest-agent`
(so Proxmox can read VM state), `cloud-init` (first-boot config), and
`sudo` (Ansible privilege escalation). Credentials inject at build time
via the Infisical CLI, never stored in code.

### Why separate Terraform and Ansible?

Terraform provisions infrastructure (VMs, networks, disks). Ansible
configures what runs inside them (packages, services, config files).
Mixing the two into one tool makes debugging harder and breaks separation
of concerns.

### Why workspace isolation?

Each team member has a dev workspace with its own VM IDs and IP addresses.
This lets us test changes without risking the main environment. The offset
scheme (+100 for Sanjar, +200 for Jim) is simple and leaves room for
growth.

### Why two firewall layers instead of one?

Proxmox firewall runs on the host, UFW runs inside each VM. A
misconfiguration in one layer does not expose the VM because the other
still blocks the traffic. The alternative — a single dedicated firewall VM
routing all traffic — was rejected as overengineered for a six-VM lab and
harder to defend in the oral presentation. Two filters give the same
defense in depth with less code.

### Why Debian apt for Prometheus instead of the official Ansible collection?

The `prometheus.prometheus` collection from Galaxy provides newer
Prometheus versions (2.50+) and a standardized layout. The Debian apt
package ships Prometheus 2.42, which is older but receives security
updates through the Debian-stable channel. For our fleet of six VMs the
feature gap is not relevant, while the security update path matters every
month. The apt approach also adds zero extra Galaxy dependencies. A team
running 100+ targets or following Prometheus releases closely would
choose the collection.

### Why Grafana behind the load balancer instead of its own port?

Exposing Grafana on port 3000 would require opening another port on the
firewall and giving operators a second URL to remember. Routing through
`http://lb-01/grafana` keeps a single entry point and lets us add
authentication, TLS, or rate limiting at one place. The cost is two
Grafana config lines (`root_url` and `serve_from_sub_path`).

### Why pgaudit logs DDL and WRITE instead of WRITE only?

WRITE alone catches data changes (INSERT, UPDATE, DELETE). DDL catches
schema changes (CREATE, ALTER, DROP). Schema changes happen rarely but
are critical in an incident — if someone drops a table, we want it in
the audit trail. Adding DDL is a one-word config change and the volume
impact is negligible.

---

## Iterations

The project builds in five iterations. Each adds a layer on top of the
previous one.

| # | Iteration | Status |
|---|-----------|--------|
| 1 | Foundation: control-node, Terraform pipeline, Ansible structure | Merged to main, 11/11 checks pass |
| 2 | Three-tier: Flask + PostgreSQL with TLS | Merged to main, 14/14 checks pass |
| 3 | Load balancing: Nginx LB + second web server + dynamic inventory | Merged to main, 11/11 checks pass |
| 4 | Network hardening: UFW + Proxmox firewall + SSH hardening (`devsec.hardening`) | Merged to main, 24/24 checks pass |
| 5 | Monitoring + auditing: Prometheus, Grafana, Alertmanager, node_exporter, postgres_exporter, pgaudit | Merged to main, 26/26 checks pass |

---

## Team

- **Sanjar Baghchehsaraee** ([@sanjarbsaraee](https://github.com/sanjarbsaraee)) — primary infrastructure owner
- **Jim Mickelsson** ([@jim-mickelsson](https://github.com/jim-mickelsson)) — collaborator

---

*Course: Virtualization Technology and Automation (ITS25)*
*Program: IT Security Engineering, Yrkeshögskolan i Enköping*
