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
   +----------+----------+----------+
   |          |          |          |
control-node web-01    db-01      future VMs
 (Ansible)   (Nginx)  (PostgreSQL)  added per iteration
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
| `web-01` | Web server | 192.168.50.20 | 2 | Nginx, serves the application |
| `db-01` | Database server | 192.168.50.30 | 2 | PostgreSQL 16, access restricted to web tier in iter 2 |

---

## Repository structure

```
.
├── terraform/
│   ├── terraform.tf              # Backend (HCP) and required providers
│   ├── providers.tf              # Connects to Infisical and Proxmox
│   ├── variables.tf              # Input variables with defaults
│   ├── data.tf                   # Pulls secrets from Infisical
│   ├── main.tf                   # VM and cloud-init resources
│   ├── outputs.tf                # IPs and VM IDs for Ansible
│   └── ansible-bootstrap.yaml    # Cloud-init template for control-node
│
├── ansible/
│   ├── ansible.cfg               # Paths, output format, SSH pipelining
│   ├── inventories/prod/
│   │   └── hosts.yml             # Host groups mapped to plays
│   ├── playbooks/
│   │   └── site.yml              # Orchestrator, one play per group
│   ├── roles/
│   │   └── control_node_check/   # Verifies packages and connectivity
│   └── collections/
│       └── requirements.yml      # Galaxy collections (Infisical, PostgreSQL)
│
├── scripts/
│   └── verify-iter1.sh           # 11 checks run from a laptop over SSH
│
├── docs/                         # Setup guides and design records
└── .gitignore
```

Terraform follows HashiCorp's standard module structure. Ansible roles live under `ansible/roles/`, one directory per role. New roles are added as iterations progress.

---

## Components

### Terraform

Provisions VMs on Proxmox using the `bpg/proxmox` provider. Each VM is cloned from a Debian 12 cloud-init template (VM ID 9000). The `main.tf` file contains a workspace-aware mapping that assigns unique VM IDs and IP addresses per environment, so our dev VMs never interfere with each other or with main.

### Ansible

Configures VMs after they boot. Playbooks run from the control-node, not from our laptops. The `site.yml` file maps each host group to its roles. Currently the only role is `control_node_check`, which verifies that Ansible, Git and Python are present, checks disk space and reports the host identity.

### Infisical

Stores the Proxmox API token, the SSH private key for the Terraform bot, and our public SSH keys. Terraform reads these at apply time. Nothing secret lives in the repo or on local disk.

### HCP Terraform

Stores Terraform state remotely so we both work against the same state file. Three workspaces (main, sanjar-dev, jim-dev) share the same Infisical secrets. A self-hosted agent on the Proxmox host executes plans and applies, since HCP's cloud runners cannot reach our Tailscale network.

### Cloud-init

A YAML snippet (`ansible-bootstrap.yaml`) that Proxmox passes to the control-node at first boot. It creates the `admin` user, installs packages, clones this repo and installs Galaxy collections. This is what makes the two-command flow possible.

---

## Prerequisites

**On your Windows laptop:**

- [Terraform CLI](https://developer.hashicorp.com/terraform/install)
- [Git](https://git-scm.com/) (includes Git Bash)
- An SSH key pair for VM access
- Tailscale connected to the mesh network

**Accounts:**

- HCP Terraform (organization: `its25-virt-automation`)
- Infisical (project secrets configured)

**On the Proxmox host:**

- Debian 12 cloud-init template at VM ID 9000
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

# 4. SSH into the control-node
ssh admin@192.168.50.10 -i ~/.ssh/your_vm_key

# 5. Run the playbook
cd ~/its25-virt-automation/ansible
ansible-playbook playbooks/site.yml

# 6. Exit the control-node
exit

# 7. Verify from your laptop (from the repo root)
cd ../its25-virt-automation
./scripts/verify-iter1.sh 192.168.50.10
```

After step 5, running the playbook a second time should show `changed=0`, confirming that nothing changed unnecessarily.

---

## Secrets

All secrets live in Infisical, never in the repo. Terraform reads them at apply time through the `infisical` provider.

| Secret | Purpose |
|---|---|
| `PROXMOX_API_TOKEN` | Authenticates Terraform against the Proxmox API |
| `TERRAFORM_BOT_PRIVATE_KEY` | SSH key the provider uses to upload cloud-init snippets |
| `SANJAR_VM_PUBLIC_KEY` | Sanjar's public key, injected into VMs |
| `JIM_VM_PUBLIC_KEY` | Jim's public key, injected into VMs |

The same secrets are configured in all three HCP Terraform workspaces so that each environment can provision independently.

---

## Security measures

*Added in iteration 5.*

---

## Security analysis

*Added in iteration 5.*

---

## Verification

From a laptop with SSH access to the control-node:

```bash
./scripts/verify-iter1.sh 192.168.50.10
```

The script SSHs into the control-node and runs 11 checks:

| Category | What it checks |
|---|---|
| Connectivity | SSH login, hostname |
| Packages | Ansible, Git, Python 3 installed |
| Repository | Repo cloned, playbook and role exist |
| Galaxy | Infisical collection installed |
| Playbook | First run succeeds, second run is idempotent |

Expected output:

```
==========================================
 Iter 1 verification — control-node 192.168.50.10
==========================================

--- Connectivity ---
✓ SSH works as admin
✓ Hostname resolves

--- Packages (from cloud-init) ---
✓ Ansible installed
✓ Git installed
✓ Python 3 installed

--- Repository (from cloud-init runcmd) ---
✓ Repo cloned
✓ Playbook exists
✓ Role exists

--- Galaxy collections (from cloud-init runcmd) ---
✓ Infisical collection installed

--- Playbook execution ---
✓ Playbook first run succeeds
✓ Playbook second run is idempotent (changed=0)

==========================================
Results: 11 passed, 0 failed
==========================================
```

---

## Design choices

### Why Proxmox instead of VirtualBox?

Proxmox is a type 1 hypervisor that runs directly on hardware. VirtualBox is type 2 and runs on top of Windows. Proxmox gives us an environment closer to production and lets us use Terraform with a real provider instead of Vagrant. For a project targeting VG, this shows we can work with the same tools used in production.

### Why Infisical instead of Ansible Vault?

Ansible Vault encrypts files at rest, but the decrypted values still end up on disk during a play. Infisical serves secrets over an API at the moment Terraform needs them. No secret file ever touches the repo or local disk. Adding a new team member means granting Infisical access, not distributing a shared vault password.

### Why separate Terraform and Ansible?

Terraform provisions infrastructure (VMs, networks, disks). Ansible configures what runs inside them (packages, services, config files). Mixing the two into one tool makes debugging harder and breaks separation of concerns.

### Why workspace isolation?

We each have a dev workspace with its own VM IDs and IP addresses. This lets us test changes without risking the main environment. The offset scheme (+100 for Sanjar, +200 for Jim) is simple and leaves room for growth.

*More design choices added as iterations progress.*

---

## Iterations

We build the project in five iterations. Each adds a layer on top of the previous one.

| # | Iteration | Status |
|---|-----------|--------|
| 1 | Foundation: control-node, Terraform pipeline, Ansible structure | 11/11 checks pass. PR pending merge. |
| 2 | Three-tier: Nginx + PostgreSQL | Planned |
| 3 | Load balancing: HAProxy + second web server | Planned |
| 4 | Network segmentation: firewall, VLAN | Planned |
| 5 | Monitoring + hardening: Prometheus, Grafana, Wazuh, CIS benchmarks | Planned |

---

## Team

- **Sanjar Baghchehsaraee** ([@sanjarbsaraee](https://github.com/sanjarbsaraee)) — primary infrastructure owner
- **Jim Mickelsson** ([@jim-mickelsson](https://github.com/jim-mickelsson)) — collaborator

---

*Course: Virtualization Technology and Automation (ITS25)*
*Program: IT Security Engineering, Yrkeshögskolan i Enköping*
