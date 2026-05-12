# Product Context - ITS25 Virtualization Automation

## Project Name
ITS25 Virtualization Automation

## Core Objectives
To build a fully automated, secure, and reproducible Proxmox infrastructure using Infrastructure as Code (Terraform) and Configuration Management (Ansible). The project demonstrates defense-in-depth security, load balancing, and centralized monitoring.

## Business Rules / Grading Criteria
*   **Säkerhet (Security):** Defense in depth (Proxmox firewall + UFW), principle of least privilege, disabled root SSH, brute-force protection.
*   **Robusthet (Robustness):** Idempotent playbooks, handling of transient network drops (increased timeouts), reproducible from scratch.
*   **Skalbarhet (Scalability):** Dynamic inventory, security groups mapped to roles rather than hardcoded IPs.

## Tech Stack
*   **Hypervisor:** Proxmox VE
*   **IaC:** Terraform (with `bpg/proxmox` provider)
*   **Config Management:** Ansible
*   **Database:** PostgreSQL 16 (with `pgAudit`)
*   **Web Framework:** Python Flask
*   **Load Balancer:** Nginx
*   **Monitoring:** Prometheus, Grafana, Alertmanager
