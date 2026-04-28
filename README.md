# its25-virt-automation

Infrastructure-as-code project on Proxmox VE using Terraform for provisioning and Ansible for configuration. Capstone for the course Virtualization Technology and Automation (ITS25) at Yrkeshögskolan i Enköping.

## Overview

The project builds a virtualized environment in five iterations, each adding a layer of capability. Every iteration is fully automated, meaning a destroy-and-rebuild cycle produces the same environment every time.

- **Terraform** provisions VMs and network resources on Proxmox, using the `bpg/proxmox` provider.
- **Ansible** configures the VMs after they boot. Playbooks run from the control-node VM, not from operator laptops.
- **Infisical** stores secrets (API tokens, private SSH keys) and serves them to Terraform at run time, so no secrets live on disk in plain text.
- **HCP Terraform** stores remote state and orchestrates plan and apply runs. A self-hosted agent on the Proxmox host executes the actual Terraform operations, since HCP's cloud runners cannot reach the Tailscale network where the host lives.
- **Tailscale** provides secure remote access to the Proxmox host without exposing port 8006 to the internet.

## Design philosophy

This is a course capstone targeting the highest grade (VG), not a production system. Two principles guide every architecture choice:

1. **VG-criteria-driven design.** Every choice maps to a stated grade requirement: scalability, robustness, redundancy, or security. If a choice does not, it is dropped.
2. **Minimum effective dose.** Complexity is added only when it solves a concrete present problem, never a hypothetical future one.

Best practice is contextual. What suits a production team of ten can be overengineering for a two-student course project.

## Architecture

```
        Team laptops (Sanjar, Jim)
                  |
                  |  Tailscale mesh VPN
                  |  (WireGuard, end-to-end encrypted)
                  |
          Proxmox VE host (GEEKOM A5)
                  |    |
                  |    +-- HCP Terraform agent (systemd service)
                  |
       +----------+----------+----------+
       |          |          |          |
   control-node  web-01   db-01      ...           Application VMs
   (Ansible)    Nginx    Postgres                  deployed per iteration
```

Two-command operator flow per iteration: `terraform apply` from a laptop, then SSH to the control-node and run `ansible-playbook site.yml`. Cloud-init installs Ansible, git, and python3-pip on the control-node so the second command works immediately after first boot.

## Repository structure

```
.
├── docs/
│   ├── setup/                       How we set things up, step by step
│   ├── architecture/                Design decisions and rationale
│   └── changes-from-jims-base.md    Iter 1 deltas from the base branch
├── terraform/                       VM and network provisioning
│   ├── terraform.tf                 Backend and required_providers
│   ├── providers.tf                 Provider configuration
│   ├── variables.tf                 Input variables
│   ├── data.tf                      Data sources and locals
│   ├── main.tf                      Resources
│   ├── outputs.tf                   Outputs
│   ├── ansible-bootstrap.yaml       Cloud-init snippet template
│   └── .ssh/                        Public SSH keys (private keys live in Infisical)
└── ansible/                         Configuration management
    ├── inventories/prod/
    ├── playbooks/
    └── roles/
```

The `terraform/` directory follows HashiCorp's Standard Module Structure.

## Iterations

| # | Iteration | Status |
|---|-----------|--------|
| 1 | Foundation and VPN access | Functionally complete (2026-04-27). Ansible structure in git done and merged to main. |
| 2 | Web server and database, three-tier | Planned |
| 3 | Load balancing and scalability | Planned |
| 4 | Firewall and network segmentation | Planned |
| 5 | Monitoring and hardening | Planned |

## Documentation

- [Tailscale setup on the Proxmox host](docs/setup/tailscale-on-host.md)
- [Proxmox host setup](docs/setup/proxmox-host.md)

More documents are added as the project progresses.

## Team

- Sanjar Baghchehsaraee ([@sanjarbsaraee](https://github.com/sanjarbsaraee)), primary infrastructure owner
- Jim Mickelsson ([@jim-mickelsson](https://github.com/jim-mickelsson)), collaborator

## Course context

This is the capstone project for ITS25, part of the IT Security Engineer program at Yrkeshögskolan i Enköping. The grade scale is IG, G, and VG. The target is VG, which requires a threat model, automated verification, and an architect perspective on the choices made.
