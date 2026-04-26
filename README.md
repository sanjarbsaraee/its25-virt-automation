# its25-virt-automation

Infrastructure-as-code project on Proxmox VE using Terraform for provisioning and Ansible for configuration. Capstone for the course Virtualization Technology and Automation (ITS25) at Yrkeshögskolan i Enköping.

## Overview

The project builds a virtualized environment in five iterations, each adding a layer of capability. Every iteration is fully automated, meaning a destroy-and-rebuild cycle produces the same environment every time.

- **Terraform** provisions VMs and network resources on Proxmox, using the `bpg/proxmox` provider.
- **Ansible** configures the VMs after they boot, using the `community.proxmox` collection.
- **Infisical** stores secrets (API tokens, private SSH keys) and serves them to Terraform at run time, so no secrets live on disk in plain text.
- **HCP Terraform** stores remote state and orchestrates plan and apply runs. A self-hosted agent on the Proxmox host executes the actual Terraform operations, since HCP's cloud runners cannot reach the Tailscale network where the host lives.
- **Tailscale** provides secure remote access to the Proxmox host without exposing port 8006 to the internet.

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
       +----------+----------+
       |          |          |
     web-01   app-01     db-01          Application VMs,
     Nginx    Flask     Postgres        deployed per iteration
```

Terraform runs flow: `terraform apply` from a laptop → HCP Terraform → agent on Proxmox host → bpg/proxmox provider → Proxmox API → VM created.

## Repository structure

```
.
├── docs/
│   ├── setup/                  How we set things up, step by step
│   ├── architecture/           Design decisions and rationale
│   └── iterations/             What was delivered per iteration
├── terraform/                  VM and network provisioning
│   ├── terraform.tf            Backend and required_providers
│   ├── providers.tf            Provider configuration
│   ├── variables.tf            Input variables
│   ├── data.tf                 Data sources and locals
│   ├── main.tf                 Resources
│   ├── outputs.tf              Outputs
│   └── .ssh/                   Public SSH keys (private keys live in Infisical)
└── ansible/                    Configuration management
    ├── inventory/
    ├── playbooks/
    ├── roles/
    └── group_vars/
```

The `terraform/` directory follows HashiCorp's Standard Module Structure.

## Iterations

| # | Iteration | Status |
|---|-----------|--------|
| 1 | Foundation and VPN access | Terraform foundation complete, Ansible pending |
| 2 | Web server and database, three-tier | Planned |
| 3 | Load balancing and scalability | Planned |
| 4 | Firewall and network segmentation | Planned |
| 5 | Monitoring and hardening | Planned |

## Documentation

- [Tailscale setup on the Proxmox host](docs/setup/tailscale-on-host.md)

More documents are added as the project progresses.

## Team

- Sanjar Baghchehsaraee ([@sanjarbsaraee](https://github.com/sanjarbsaraee)), primary infrastructure owner
- Jim Mickelsson ([@jim-mickelsson](https://github.com/jim-mickelsson)), collaborator

## Course context

This is the capstone project for ITS25, part of the IT Security Engineer program at Yrkeshögskolan i Enköping. The grade scale is IG, G, and VG. The target is VG, which requires a threat model, automated verification, and an architect perspective on the choices made.
