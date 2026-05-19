# its25-virt-automation

Production-shaped virtualization lab on a single mini PC, driven entirely
by code. Five iterations build the stack from a bare Proxmox host to a
load-balanced, monitored, audit-logged web application.

```
terraform apply                            # provisions all VMs (~5 min)
ansible-playbook -i inventories/prod \     # configures everything inside
   /proxmox.yml playbooks/site.yml
```

Two commands. End-to-end reproducible. Verified by one script per
iteration (`scripts/verify-iter*.sh`).

---

## Table of contents

- [Architecture](#architecture)
- [Iterations](#iterations)
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
- [Team](#team)

---

## Architecture

```
    Operator laptops (Windows, PowerShell + Git Bash)
              |
              |  Tailscale (WireGuard tunnel, no open ports)
              |
   tailscale-gw LXC on Proxmox host (192.168.50.5)
              |
              |  advertises 192.168.50.0/24 to the tailnet
              |
      Proxmox VE host (GEEKOM A5, 16 GB RAM, 192.168.50.197)
              |
              +-- HCP Terraform agent (runs plans and applies)
              |
   +----------+----------+----------+----------+----------+
   |          |          |          |          |          |
control-node lb-01    web-01    web-02     db-01    monitor-01
 (Ansible)   (Nginx LB) (Flask)  (Flask)  (PostgreSQL) (Prometheus+
                                          (pgaudit)    Grafana)
```

We work from Windows laptops. **Tailscale** (a WireGuard-based mesh VPN
where every device authenticates through a central identity provider)
gives access to the Proxmox host without exposing its management port to
the internet. A dedicated `tailscale-gw` LXC container on the host runs
as the subnet router, advertising `192.168.50.0/24` to the tailnet so
operators reach all VMs through one tunnel. The **HCP Terraform agent**
(a self-hosted runner that polls the Hashicorp Cloud Platform for jobs
to execute) runs on the host, because HCP's hosted runners cannot reach
a private Tailscale network.

Each iteration deploys in two commands:

1. `terraform apply` from a laptop provisions or updates VMs.
2. SSH into the control-node and run `ansible-playbook playbooks/site.yml`.

**Cloud-init** (the industry-standard tool that runs first-boot
configuration from a YAML file) installs Ansible, Git, and Python on the
control-node at first boot, clones this repo, and installs Galaxy
collections. Step 2 works immediately, no manual setup needed.

---

## Iterations

The project builds in five iterations. Each adds a layer on top of the
previous one and is gated by a verification script that must pass before
merge.

| # | Iteration | What it adds | Status |
|---|---|---|---|
| 1 | Foundation | control-node, Terraform pipeline, Ansible structure, Packer template | Merged, 11/11 checks pass |
| 2 | Three-tier | Flask + Gunicorn web tier, PostgreSQL 16 with TLS | Merged, 14/14 checks pass |
| 3 | Load balancing | nginx reverse proxy, second web server, dynamic inventory | Merged, 11/11 checks pass |
| 4 | Network hardening | UFW per VM, Proxmox firewall, SSH hardening via `devsec.hardening` | Merged, 24/24 checks pass |
| 5 | Monitoring + auditing | Prometheus, Grafana, Alertmanager, node_exporter, postgres_exporter, pgaudit | Merged, 28/28 checks pass |

Iteration-by-iteration design documents and verification scripts live
under `docs/` and `scripts/`.

---

## VMs and IP addresses

Each HCP Terraform workspace (`its25-virt-automation`, `its25-sanjar-dev`,
`its25-jim-dev`) shifts VM IDs and IPs so parallel environments never
collide. The table below shows the `its25-virt-automation` (main)
workspace. Dev workspaces add an offset of 100 (Sanjar) or 200 (Jim) to
the base IP.

| VM | Role | IP address | Iteration | Description |
|---|---|---|---|---|
| `control-node` | Ansible controller | 192.168.50.10 | 1 | Runs playbooks against all other VMs |
| `web-01` | Web server | 192.168.50.20 | 2 | Flask + Gunicorn, serves the application |
| `web-02` | Web server | 192.168.50.21 | 3 | Second backend behind the load balancer |
| `db-01` | Database server | 192.168.50.30 | 2 | PostgreSQL 16, TLS, pgaudit |
| `lb-01` | Load balancer | 192.168.50.40 | 3 | Nginx, round-robin to web-01 and web-02 |
| `monitor-01` | Monitoring server | 192.168.50.50 | 5 | Prometheus, Grafana, Alertmanager, postgres_exporter |

A separate LXC container (`tailscale-gw`) at `192.168.50.5` runs the
Tailscale subnet router. The Proxmox host itself sits at `192.168.50.197`
on the LAN and `100.94.227.10` on the tailnet.

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
│       └── requirements.yml      # Galaxy collection pins (single source of truth)
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
│   ├── verify-iter5.sh           # 28 checks for monitoring, pgaudit, exporters
│   └── verify-node.sh            # General health check for any VM
│
├── docs/                         # Setup guides and design records
└── .gitignore
```

Terraform follows HashiCorp's standard module structure. Ansible roles
live under `ansible/roles/`, one directory per role. **Packer** (the
HashiCorp tool that builds VM images from a config file) creates the
golden template that all VMs clone from. New roles arrive with each
iteration.

---

## Components

### Terraform

Provisions VMs on Proxmox using the `bpg/proxmox` provider (pinned to
`0.103.0` in `terraform.tf`). Each VM clones from a Debian 12 golden
template (VM ID 9001) built by Packer. The `main.tf` file uses a single
`for_each` loop (a Terraform meta-argument that creates one resource per
item in a map) over a `vm_fleet` map, so adding a new VM means adding
one line. A workspace-aware mapping assigns unique VM IDs and IP
addresses per environment, so dev VMs never interfere with each other
or with main.

### Ansible

Configures VMs after they boot. Playbooks run from the control-node, not
from our laptops, so the workflow does not depend on which laptop is
online. The `site.yml` file maps each host group to its roles.

Roles:

- `control_node_check` verifies packages and connectivity
- `common` installs baseline packages, sets the timezone, enables UFW
  with default-deny, and installs `node_exporter` (the Prometheus agent
  that exposes machine metrics on port 9100)
- `flask_app` deploys Flask behind Gunicorn as a systemd service
- `postgres_server` installs PostgreSQL 16 with TLS, enables `pgaudit`
  (a PostgreSQL extension that logs every executed query) for DDL and
  WRITE statements, and creates the `exporter` read-only user
- `nginx_lb` configures Nginx as a round-robin load balancer and
  proxies `/grafana` to monitor-01:3000
- `prometheus_server` installs Prometheus, Alertmanager, Grafana, and
  `postgres_exporter` (the Prometheus agent that exposes database
  metrics on port 9187), then provisions Prometheus as the default
  Grafana data source

Galaxy collection dependencies are pinned in
`ansible/collections/requirements.yml` (currently `infisical.vault`,
`community.postgresql`, and `community.proxmox`). The pin-file is the
single source of truth for reproducible installs.

Database passwords come from Infisical at runtime through the
`infisical.vault` lookup. No secrets touch the disk on the control-node.

Since iteration 3, Ansible uses dynamic inventory through the
`community.proxmox.proxmox` plugin instead of a static `hosts.yml`. The
plugin queries the Proxmox API at every invocation and filters VMs by
workspace suffix, so the three workspaces stay isolated on the same host.

### Packer

Automates the creation of the golden template (ID 9001). Without it,
template builds take 10+ minutes per install with risk of inconsistency
between VMs. The **preseed** file (an unattended-install config that
answers every Debian installer prompt automatically) answers every
prompt without operator input. Packer credentials live in Infisical and
are injected at runtime through the Infisical CLI:

```bash
infisical run -- packer build .
```

### Infisical

Stores the Proxmox API token, the SSH private key for the Terraform bot,
Packer credentials, the database password, the exporter password, and
our public SSH keys. Terraform reads these at apply time through the
`infisical` provider. Nothing secret lives in the repo or on local disk.

Ansible reads runtime secrets through the `infisical.vault` lookup,
which uses **Universal Auth** (Infisical's machine-identity flow that
exchanges a long-lived Client ID + Secret for short-lived access tokens).
The control-node receives the Client ID and Secret through cloud-init at
first boot.

### HCP Terraform

Stores Terraform state remotely so we both work against the same state
file. Three workspaces (`its25-virt-automation`, `its25-sanjar-dev`,
`its25-jim-dev`) share the same Infisical secrets. A self-hosted agent
on the Proxmox host executes plans and applies, since HCP's hosted
runners cannot reach our Tailscale network. The agent talks to the
Proxmox API at `https://192.168.50.197:8006/` over the local LAN, not
through the tailnet, so Terraform traffic skips the subnet-routing path.

### Cloud-init

A YAML snippet (`ansible-bootstrap.yaml`) that Proxmox passes to the
control-node at first boot. Cloud-init creates the `automation` user,
installs packages, clones this repo, writes the Infisical credentials to
`/etc/environment`, and installs Galaxy collections (bundled Ansible
modules distributed through the official Ansible Galaxy registry). This
setup makes the two-command flow possible.

### Firewall

Two filter layers block traffic to each VM. The Proxmox firewall runs on
the host and filters before the packet reaches the VM. UFW runs inside
each VM and filters again. A bug in either layer does not expose the VM,
because the other still blocks the traffic.

Proxmox rules live in `terraform/firewall.tf` as reusable cluster
security groups. Iteration 4 added four base groups (`ssh-from-mgmt`,
`http-public`, `flask-from-lb-*`, `pg-from-web-*`); iteration 5 added
three more for the monitoring stack (`pg-from-mon-*`, `nodexp-from-mon-*`,
`grafana-from-lb-*`). Groups with role-specific scope are suffixed with
the workspace name (`flask-from-lb-sanjar`, `flask-from-lb-jim`,
`flask-from-lb` for main) so the three environments can apply
independently without name collisions. Each VM binds the groups its role
needs through a single `firewall_rules` resource.

UFW rules live in the Ansible roles: a baseline in `common`
(default-deny incoming, rate-limited SSH from LAN and Tailscale) and
role-specific allows in each component role.

SSH hardening uses the `devsec.hardening.ssh_hardening` role from Galaxy
(a CIS-benchmark-aligned set of Ansible roles maintained by the DevSec
project). Root login and password authentication are both disabled.

### Monitoring stack

Iteration 5 adds a dedicated monitoring VM (`monitor-01`) running four
services:

- **Prometheus** scrapes metrics from every VM every 15 seconds and
  stores them in a time-series database
- **Alertmanager** routes alerts produced by Prometheus rules to the
  configured channels
- **Grafana** displays the data in dashboards, reachable through
  `http://lb-01/grafana`
- **postgres_exporter** queries db-01 with the read-only `exporter`
  user and publishes database metrics

Every VM runs `node_exporter` on port 9100. The `pg-from-mon-*` security
group allows monitor-01 to query db-01:5432 through the firewall. The
`grafana-from-lb-*` group restricts port 3000 to lb-01, so Grafana is
unreachable from anywhere else on the network.

Database auditing on db-01 uses `pgaudit` configured to log DDL (schema
changes like `CREATE`, `ALTER`, `DROP`) and WRITE (data changes like
`INSERT`, `UPDATE`, `DELETE`). The `pg_stat_statements` extension tracks
query performance statistics for slow-query analysis. Logrotate caps
audit log size at 100 MB per file with daily rotation.

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
with their own key paths. **ProxyJump** (an SSH feature that tunnels a
connection through an intermediate host) routes through the Proxmox host
so VMs are reachable even outside the home LAN.

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
- Tailscale connected; `tailscale-gw` LXC running and advertising
  `192.168.50.0/24`

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

# 6. Verify (from a laptop, takes about 30 seconds)
bash scripts/verify-iter5.sh 192.168.50.10 192.168.50.20 \
     192.168.50.21 192.168.50.30 192.168.50.40 192.168.50.50
```

After step 5, a second playbook run shows `changed=0`. The infrastructure
is idempotent, so running the same playbook twice has the same effect as
running it once.

After step 6, open `http://192.168.50.40/grafana` in a browser. Default
login is `admin / admin`; Grafana asks for a new password on first
sign-in. Prometheus is pre-configured as the default data source.

---

## Secrets

All secrets live in Infisical, never in the repo. Terraform reads them
at apply time through the `infisical` provider. Ansible reads them at
playbook time through the `infisical.vault` lookup. Packer reads its
secrets through the Infisical CLI at build time.

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

The Terraform secrets exist in all three HCP Terraform workspaces so
each environment provisions independently. The Packer secrets are used
locally through `infisical run`.

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
| Application | Flask runs as non-root `automation` user through Gunicorn | `ps aux \| grep gunicorn` |
| Secrets | All secrets in Infisical, never on disk or in repo | `git log --all -- terraform.tfvars` returns empty |
| Information | `server_tokens off` in Nginx hides version | `curl -I http://lb-01/` |

Iteration 4 added the firewall layers. Iteration 5 added the database
auditing, the read-only exporter role, and Infisical-based runtime
secrets for Ansible.

---

## Security analysis

### Known remaining risks

**Single point of failure: lb-01**

The load balancer has no redundant peer. If lb-01 crashes, no traffic
reaches the web tier.

*Mitigation path:* A second LB instance with **keepalived** (a tool that
moves a virtual IP between two machines on failure) or a managed cloud
LB like AWS ALB.

*Accepted because:* The host has 16 GB RAM total. A redundant LB plus
keepalived adds two more services per VM and requires a third public IP.
The trade-off is documented.

---

**Single point of failure: monitor-01**

If monitor-01 crashes, alerts stop firing and dashboards stop updating.
The metric data also disappears, because no remote storage is configured.

*Mitigation path:* Prometheus federation with a second instance, or
remote write to a managed time-series database (Grafana Cloud, Mimir,
Thanos).

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

*Mitigation path:* Loki + Promtail (a lightweight log shipper) on each
VM, shipping to monitor-01.

*Accepted because:* Six VMs are manageable individually. Loki adds
another 500-800 MB RAM to monitor-01.

---

**Single SSH key for the `automation` account fleet-wide**

Every VM accepts the same `automation` key. Compromise of that key
compromises every host.

*Mitigation path:* Per-host keys with Ansible-Vault-stored mappings, or
short-lived certificates through an SSH CA.

*Accepted because:* The key lives only in Infisical (Terraform reads it)
and on the control-node (encrypted disk, restricted access). Rotation is
a single Infisical update plus playbook re-run.

### What protects the environment

Despite the risks above, the environment has the following defenses:

- Network segmentation: only lb-01 is reachable from outside; web and
  db tiers are behind the LAN
- Two-layer firewall (Proxmox + UFW), so a misconfiguration in one does
  not expose the VM
- Principle of least privilege: `exporter` user is read-only,
  `app_rw` cannot run DDL, `automation` is the only privileged account
- All secrets in Infisical with audit logging
- pgaudit gives a complete audit trail of who changed what in the
  database
- Idempotent infrastructure: any drift is detected by running the
  playbook again and seeing non-zero `changed=` counts

---

## Verification

One verify script per iteration plus a generic node check. Each script
runs from a laptop and SSHes into the target VMs.

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

**`verify-iter5.sh`** — 28 checks for monitoring, exporters, and pgaudit:

```bash
bash scripts/verify-iter5.sh 192.168.50.10 192.168.50.20 192.168.50.21 \
     192.168.50.30 192.168.50.40 192.168.50.50
```

| Category | Count | What it checks |
|---|---|---|
| UFW status | 6 | Active and default-deny on all 6 VMs |
| Monitoring services | 4 | Prometheus, Alertmanager, postgres_exporter, Grafana active |
| Service endpoints | 4 | `/-/healthy` on 9090, 9093, 3000/grafana, 9187 |
| Prometheus internals | 2 | `HighCpuUsage` rule loaded, `pg_up` metric published |
| node_exporter | 6 | Responds on every VM at `:9100` |
| Grafana through lb-01 | 1 | `/grafana/api/health` returns `database: ok` |
| Database (db-01) | 5 | `shared_preload_libraries` × 2, extensions × 2, `pg_monitor` role |
| **Total** | **28** | |

**`verify-node.sh`** — general health check for any VM:

```bash
bash scripts/verify-node.sh 192.168.50.10
```

The script detects whether the target is a control-node or a worker and
adjusts its checks. Useful for troubleshooting after a deploy.

---

## Design choices

### Why Proxmox instead of VirtualBox?

Proxmox is a type 1 hypervisor that runs directly on hardware.
VirtualBox is type 2 and runs on top of Windows. Proxmox gives an
environment closer to production and lets Terraform talk to a real
provider instead of going through Vagrant.

### Why Infisical instead of Ansible Vault?

Ansible Vault encrypts files at rest, but the decrypted values end up on
disk during a play. Infisical serves secrets over an API at the moment
Terraform or Ansible needs them. No secret file touches the repo or
local disk. Adding a new team member means granting Infisical access,
not distributing a shared vault password.

### Why a dedicated automation account?

A generic `admin` account for automation blurs the line between human
and machine access. The `automation` account is a dedicated service
account with passwordless sudo, used only by Ansible and cloud-init.
Human operators SSH in with their own named keys. Audit logs stay
readable, and revoking a person's access does not break automation.

### Why a golden template with Packer?

Manual template installs take 10+ minutes per build and risk
inconsistency between VMs. Packer automates the process from a preseed
file and produces a bit-perfect image every time. The template includes
`qemu-guest-agent` (a process inside the VM that lets Proxmox read VM
state like IP and hostname), `cloud-init` (first-boot config), and
`sudo` (Ansible privilege escalation). Credentials inject at build time
through the Infisical CLI, never stored in code.

### Why separate Terraform and Ansible?

Terraform provisions infrastructure (VMs, networks, disks). Ansible
configures what runs inside them (packages, services, config files).
Mixing the two into one tool makes debugging harder and breaks
separation of concerns: when a deploy fails, the two-tool split tells
us immediately whether the problem is infrastructure or configuration.

### Why workspace isolation?

Each team member has a dev workspace with its own VM IDs and IP
addresses. This lets us test changes without risking the main
environment. The offset scheme (+100 for Sanjar, +200 for Jim) is simple
and leaves room for growth. Workspace suffixes on shared global objects
(Proxmox cluster security groups like `flask-from-lb-sanjar`) prevent
collisions when all three workspaces apply against the same host.

### Why two firewall layers instead of one?

Proxmox firewall runs on the host, UFW runs inside each VM. A
misconfiguration in one layer does not expose the VM, because the other
still blocks the traffic. The alternative (a single dedicated firewall
VM routing all traffic) was rejected as over-engineered for a six-VM
lab. Two filters give defense in depth with less code.

### Why a dedicated LXC for Tailscale subnet routing?

Subnet routing first ran on the Proxmox host itself. That caused a
conntrack synchronization bug between the host's own firewall and
Tailscale's stateful filter: return traffic from VMs was dropped on
HTTP flows even though SSH worked. Moving the subnet router to a
dedicated `tailscale-gw` LXC isolates the hypervisor from subnet-routing
state and keeps the host's firewall rules out of the path.

### Why Debian apt for Prometheus instead of the official Ansible collection?

The `prometheus.prometheus` collection from Galaxy provides newer
Prometheus versions (2.50+) and a standardized layout. The Debian apt
package ships Prometheus 2.42, which is older but receives security
updates through the Debian-stable channel. For a fleet of six VMs the
feature gap is not relevant, while the security update path matters
every month. The apt approach also adds zero extra Galaxy dependencies.
A team running 100+ targets or following Prometheus releases closely
would choose the collection.

### Why Grafana behind the load balancer instead of its own port?

Exposing Grafana on port 3000 would require opening another port on the
firewall and giving operators a second URL to remember. Routing through
`http://lb-01/grafana` keeps a single entry point and lets us add
authentication, TLS, or rate limiting at one place. The cost is two
Grafana config lines (`root_url` and `serve_from_sub_path`).

### Why pgaudit logs DDL and WRITE instead of WRITE only?

WRITE alone catches data changes (INSERT, UPDATE, DELETE). DDL catches
schema changes (CREATE, ALTER, DROP). Schema changes happen rarely but
are critical in an incident: if someone drops a table, we want it in
the audit trail. Adding DDL is a one-word config change and the volume
impact is negligible.

---

## Team

- **Sanjar Baghchehsaraee** ([@sanjarbsaraee](https://github.com/sanjarbsaraee))
- **Jim Mickelsson** ([@jim-mickelsson](https://github.com/jim-mickelsson))
