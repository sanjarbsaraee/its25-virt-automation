# its25-virt-automation

Automated infrastructure on Proxmox VE. Terraform provisions VMs, Ansible configures them, Infisical stores secrets. Capstone project for the Virtualization Technology and Automation course (ITS25) at Yrkeshögskolan i Enköping.

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
control-node lb-01    web-01    web-02     db-01    (monitor-01)
 (Ansible)   (Nginx LB) (Flask)  (Flask)  (PostgreSQL) (iter 5)
```

We work from Windows laptops. Tailscale gives us access to the Proxmox host without exposing its management port to the internet. The HCP Terraform agent runs on the host because HCP's cloud runners cannot reach the Tailscale network.

We deploy in two commands per iteration:

1. `terraform apply` from a laptop provisions or updates VMs.
2. SSH into the control-node and run `ansible-playbook playbooks/site.yml`.

Cloud-init installs Ansible, Git and Python on the control-node at first boot, clones this repo and installs Galaxy collections. That makes step 2 work immediately without manual setup.

---

## VMs and IP addresses

Each HCP Terraform workspace (main, sanjar-dev, jim-dev) shifts VM IDs and IPs so parallel environments never collide. The table below shows the main workspace. Dev workspaces add an offset of 100 (Sanjar) or 200 (Jim) to the base IP.

| VM | Role | IP address | Iteration | Description |
|---|---|---|---|---|
| `control-node` | Ansible controller | 192.168.50.10 | 1 | Runs playbooks against all other VMs |
| `web-01` | Web server | 192.168.50.20 | 2 | Flask + Gunicorn, serves the application |
| `web-02` | Web server | 192.168.50.21 | 3 | Second backend behind the load balancer |
| `db-01` | Database server | 192.168.50.30 | 2 | PostgreSQL 16, access restricted to web tier |
| `lb-01` | Load balancer | 192.168.50.40 | 3 | Nginx LB, round-robin to web-01 and web-02 |
| `monitor-01` | Monitoring server | 192.168.50.50 | 5 | Prometheus + Grafana (planned) |

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
│   │       └── all/vars.yml      # db_host (dynamic), db_password (Infisical lookup)
│   ├── playbooks/
│   │   └── site.yml              # Orchestrator, one play per group
│   ├── roles/
│   │   ├── control_node_check/   # Verifies packages and connectivity
│   │   ├── common/               # Baseline packages, timezone, UFW
│   │   ├── flask_app/            # Flask + Gunicorn as systemd service
│   │   ├── postgres_server/      # PostgreSQL 16, TLS, UFW
│   │   └── nginx_lb/             # Nginx as round-robin LB
│   └── collections/
│       └── requirements.yml      # Galaxy collections
│
├── packer/
│   ├── debian-12-gold.pkr.hcl    # Builds the golden template (ID 9001)
│   └── http/
│       └── preseed.cfg           # Unattended Debian 12 install config
│
├── scripts/
│   ├── verify-iter1.sh           # 11 checks run from a laptop over SSH
│   ├── verify-iter2.sh           # 14 checks for web, db, TLS, firewall
│   ├── verify-iter3.sh           # 11 checks for LB, redundancy, end-to-end
│   ├── verify-iter4.sh           # 14 checks for firewall and SSH hardening
│   └── verify-node.sh            # General health check for any VM
│
├── docs/                         # Setup guides and design records
└── .gitignore
```

Terraform follows HashiCorp's standard module structure. Ansible roles live under `ansible/roles/`, one directory per role. Packer builds the golden template that all VMs clone from. New roles are added as iterations progress.

---

## Components

### Terraform

Provisions VMs on Proxmox using the `bpg/proxmox` provider. Each VM is cloned from a Debian 12 golden template (VM ID 9001) built by Packer. The `main.tf` file uses a single `for_each` loop over a `vm_fleet` map, so adding a new VM means adding one line. A workspace-aware mapping assigns unique VM IDs and IP addresses per environment, so dev VMs never interfere with each other or with main.

### Ansible

Configures VMs after they boot. Playbooks run from the control-node, not from our laptops. The `site.yml` file maps each host group to its roles. Five roles: `control_node_check` (verifies packages and connectivity), `common` (baseline packages, timezone, UFW with default-deny), `flask_app` (Flask behind Gunicorn as a systemd service), `postgres_server` (PostgreSQL 16 with TLS and UFW), and `nginx_lb` (Nginx as round-robin load balancer with dynamic upstream from inventory). Database passwords are fetched from Infisical at runtime via the `infisical.vault` collection.

Since iteration 3, Ansible uses dynamic inventory via the `community.proxmox.proxmox` plugin instead of a static `hosts.yml`. The plugin queries the Proxmox API at every Ansible invocation and filters VMs by workspace suffix, so Sanjar's, Jim's, and main workspaces stay isolated on the same Proxmox host.

### Packer

Automates the creation of the golden template (ID 9001). Without it, template builds are manual and take 10+ minutes per install with risk of inconsistency between VMs. The preseed file answers all Debian installer prompts automatically. Packer credentials are stored in Infisical and injected at runtime via the Infisical CLI:

```bash
infisical run -- packer build .
```

### Infisical

Stores the Proxmox API token, the SSH private key for the Terraform bot, Packer credentials and our public SSH keys. Terraform reads these at apply time through the `infisical` provider. Nothing secret lives in the repo or on local disk.

### HCP Terraform

Stores Terraform state remotely so we both work against the same state file. Three workspaces (main, sanjar-dev, jim-dev) share the same Infisical secrets. A self-hosted agent on the Proxmox host executes plans and applies, since HCP's cloud runners cannot reach our Tailscale network.

### Cloud-init

A YAML snippet (`ansible-bootstrap.yaml`) that Proxmox passes to the control-node at first boot. It creates the `automation` user, installs packages, clones this repo, writes a Terraform-generated inventory with VM names and IPs, and installs Galaxy collections. This is what makes the two-command flow possible.

### Firewall

Two filter layers block traffic to each VM. Proxmox firewall runs in the host machine and filters before the packet reaches the VM. UFW runs inside each VM and filters again. A bug in either layer does not expose the VM.

Proxmox rules are declared in `terraform/firewall.tf` as reusable cluster security groups (`ssh-from-mgmt`, `http-public`, `flask-from-lb`, `pg-from-web`). Each VM binds the groups its role needs through a single `firewall_rules` resource. UFW rules live in the Ansible roles: a baseline in `common` (default-deny incoming, rate-limited SSH from LAN and Tailscale) and role-specific allows in `flask_app`, `postgres_server`, and `nginx_lb`.

SSH hardening uses the `devsec.hardening.ssh_hardening` role from Galaxy with CIS-aligned defaults. Root login and password authentication are disabled. Verification: `bash scripts/verify-iter4.sh <ctrl> <web1> <web2> <db> <lb>`.

---

## Prerequisites

**On your Windows laptop:**

- [Terraform CLI](https://developer.hashicorp.com/terraform/install)
- [Git](https://git-scm.com/) (includes Git Bash)
- An SSH key pair for VM access
- Tailscale connected to the mesh network
- SSH config (`~/.ssh/config`) with host and VM blocks (see below)

**SSH config:**

The verify script and SSH commands rely on `~/.ssh/config` to find the right key and user. Each team member needs this file on their laptop, with their own key paths. ProxyJump routes through the Proxmox host so VMs are reachable even outside the home LAN.

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

# 3. Provision VMs
terraform apply

# 4. Wait 2-3 minutes for cloud-init, then SSH into the control-node
ssh 192.168.50.10

# 5. Run the playbook
cd ~/its25-virt-automation/ansible
ansible-playbook playbooks/site.yml

# 6. Exit the control-node
exit

# 7. Verify from your laptop (from the repo root)
cd ../its25-virt-automation
bash scripts/verify-iter1.sh 192.168.50.10
```

After step 5, running the playbook a second time should show `changed=0`, confirming that nothing changed unnecessarily.

---

## Secrets

All secrets live in Infisical, never in the repo. Terraform reads them at apply time through the `infisical` provider. Packer reads its secrets via the Infisical CLI.

| Secret | Purpose |
|---|---|
| `PROXMOX_API_TOKEN` | Authenticates Terraform against the Proxmox API |
| `TERRAFORM_BOT_PRIVATE_KEY` | SSH key the provider uses to upload cloud-init snippets |
| `SANJAR_VM_PUBLIC_KEY` | Sanjar's public key, injected into VMs |
| `JIM_VM_PUBLIC_KEY` | Jim's public key, injected into VMs |
| `AUTOMATION_PUBLIC_KEY` | Fleet SSH public key for control-node to worker |
| `AUTOMATION_PRIVATE_KEY` | Fleet SSH private key on control-node |
| `DB_PASSWORD` | PostgreSQL app_rw password, fetched by Ansible at runtime |
| `PKR_VAR_proxmox_token` | API key for Packer template builds |
| `PKR_VAR_ssh_password` | Password Packer uses to SSH in and verify install |

The Terraform secrets are configured in all three HCP Terraform workspaces so that each environment can provision independently. The Packer secrets are used locally via `infisical run`.

---

## Security measures

*Added in iteration 5.*

---

## Security analysis

*Added in iteration 5.*

---

## Verification

One verify script per iteration plus a generic node check. All run from a laptop and SSH into the target VMs.

**`verify-iter1.sh`** proves that iteration 1 works end-to-end:

```bash
bash scripts/verify-iter1.sh 192.168.50.10
```

11 checks:

| Category | What it checks |
|---|---|
| Connectivity | SSH login as `automation`, hostname set |
| Packages | Ansible, Git, Python 3 installed |
| Repository | Repo cloned, playbook and role exist |
| Galaxy | Infisical collection installed in `./collections` |
| Playbook | First run succeeds, second run is idempotent |

**`verify-iter2.sh`** proves that iteration 2 works end-to-end:

```bash
bash scripts/verify-iter2.sh 192.168.50.20 192.168.50.30
```

14 checks:

| Category | What it checks |
|---|---|
| Connectivity | SSH to web-01 and db-01 |
| Flask | GET /, /health, /info, db_reachable |
| Process | Gunicorn runs as automation, service active |
| PostgreSQL | Version 16 running, TLS cert exists |
| TLS | TLS connection succeeds, non-TLS rejected |
| Firewall | UFW active, port 5432 open from web |

**`verify-iter3.sh`** proves that iteration 3 works end-to-end:

```bash
bash scripts/verify-iter3.sh 192.168.50.40 192.168.50.20 192.168.50.21
```

Arguments: lb-01 IP, web-01 IP, web-02 IP. 11 checks:

| Category | What it checks |
|---|---|
| Connectivity | SSH to lb-01, web-01, web-02 |
| Nginx | Service running, listening on port 80 |
| Round-robin | Multiple requests hit different backends |
| Failover | Stopping a backend removes it from the pool |
| `server_tokens off` | HTTP response does not leak Nginx version |
| Idempotence | Re-running playbook shows `changed=0` |

**`verify-iter4.sh`** proves that iteration 4 works end-to-end:

```bash
bash scripts/verify-iter4.sh 192.168.50.10 192.168.50.20 192.168.50.21 192.168.50.30 192.168.50.40
```

Arguments: control-node, web-01, web-02, db-01, lb-01. 14 checks:

| Category | What it checks |
|---|---|
| UFW status | Active and default-deny on every VM |
| SSH hardening | Root login disabled, password auth disabled |
| Allowed traffic | lb-01 reaches web-01:8080, web-01 reaches db-01:5432 |
| Blocked traffic | db-01 cannot reach web-01:8080, lb-01 cannot reach db-01:5432 |

**`verify-node.sh`** checks general health on any VM:

```bash
bash scripts/verify-node.sh 192.168.50.10
```

It detects whether the target is a control-node or a worker and adjusts its checks accordingly. Useful for troubleshooting after a deploy.

---

## Design choices

### Why Proxmox instead of VirtualBox?

Proxmox is a type 1 hypervisor that runs directly on hardware. VirtualBox is type 2 and runs on top of Windows. Proxmox gives us an environment closer to production and lets us use Terraform with a real provider instead of Vagrant. For a project targeting VG, this shows we can work with the same tools used in production.

### Why Infisical instead of Ansible Vault?

Ansible Vault encrypts files at rest, but the decrypted values still end up on disk during a play. Infisical serves secrets over an API at the moment Terraform needs them. No secret file ever touches the repo or local disk. Adding a new team member means granting Infisical access, not distributing a shared vault password.

### Why a dedicated automation account?

Using a generic `admin` account for automation blurs the line between human access and machine access. The `automation` account is a dedicated service account with passwordless sudo, used only by Ansible and cloud-init. Human operators SSH in with their own named keys. This follows the principle of least privilege and makes audit logs easier to read.

### Why a golden template with Packer?

Manual template installs take 10+ minutes and risk inconsistency between builds. Packer automates the process from a preseed file, producing a bit-perfect image every time. The template includes `qemu-guest-agent` (lets Proxmox read VM state), `cloud-init` (first-boot config), and `sudo` (Ansible privilege escalation). Credentials are injected at build time via Infisical CLI, never stored in code.

### Why separate Terraform and Ansible?

Terraform provisions infrastructure (VMs, networks, disks). Ansible configures what runs inside them (packages, services, config files). Mixing the two into one tool makes debugging harder and breaks separation of concerns.

### Why workspace isolation?

We each have a dev workspace with its own VM IDs and IP addresses. This lets us test changes without risking the main environment. The offset scheme (+100 for Sanjar, +200 for Jim) is simple and leaves room for growth.

### Why two firewall layers instead of one?

Proxmox firewall runs in the host machine, UFW runs inside each VM. If we misconfigure one or a bug slips through, the other still blocks the traffic. The alternative, a single dedicated firewall VM routing all traffic, was rejected as overengineered for a five-VM lab and harder to defend in the oral presentation. Two filters give the same defense in depth with far less code.

*More design choices added as iterations progress.*

---

## Iterations

We build the project in five iterations. Each adds a layer on top of the previous one.

| # | Iteration | Status |
|---|-----------|--------|
| 1 | Foundation: control-node, Terraform pipeline, Ansible structure | Merged to main, 11/11 checks pass |
| 2 | Three-tier: Flask + PostgreSQL with TLS | Merged to main, 14/14 checks pass |
| 3 | Load balancing: Nginx LB + second web server + dynamic inventory | Merged to main, 11/11 checks pass |
| 4 | Network hardening: UFW + Proxmox firewall + SSH hardening (`devsec.hardening`) | Documented, ready to verify on `iter4-test` |
| 5 | Monitoring + hardening: Prometheus, Grafana, node_exporter, pgaudit, `devsec.hardening.os_hardening`, Goss | Planned |

---

## Team

- **Sanjar Baghchehsaraee** ([@sanjarbsaraee](https://github.com/sanjarbsaraee)) — primary infrastructure owner
- **Jim Mickelsson** ([@jim-mickelsson](https://github.com/jim-mickelsson)) — collaborator

---

*Course: Virtualization Technology and Automation (ITS25)*
*Program: IT Security Engineering, Yrkeshögskolan i Enköping*
