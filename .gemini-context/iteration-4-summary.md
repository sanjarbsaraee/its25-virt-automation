# Iteration 4 Verification and Fixes Overview

This document summarizes the changes applied during the verification phase of Iteration 4 to resolve network timeouts, resource exhaustion, and bootstrap failures.

## 1. Resource Optimization (Terraform)
To prevent the Proxmox host from running out of memory and suffering from disk I/O starvation during parallel deployments, the following adjustments were made in `terraform/main.tf`:
*   **Linked Clones:** Switched `full = true` to `full = false` in the VM clone block. This forces Proxmox to use linked clones instead of full copies, reducing deployment time from minutes to seconds and saving massive amounts of storage.
*   **Memory Reduction:** Halved the memory for most VMs. 
    *   `control-node`: 2048 MB (Kept high for Ansible operations)
    *   `db-01`: 1024 MB (Kept high enough for PostgreSQL shared buffers)
    *   `web-01`, `web-02`, `lb-01`: Reduced to 512 MB.

## 2. Firewall and Security Group Fixes (Terraform)
During the execution of the verification script, traffic from the Load Balancer to the Web servers (port 8080) and from the Web servers to the Database (port 5432) timed out despite correct UFW rules.
*   **Fix:** Added `enabled = true` to the rules inside the `proxmox_virtual_environment_cluster_firewall_security_group` resources in `terraform/firewall.tf`. The Proxmox provider defaults these to disabled if not explicitly stated, causing packets to be silently dropped.

## 3. Ansible and Bootstrap Improvements
*   **SSH Timeout:** Increased the default timeout in `ansible/ansible.cfg` to `30` seconds. This prevents transient "UNREACHABLE" errors when heavy I/O load or service restarts cause brief network lag.
*   **Path Resolution:** Replaced manual `PATH` exports in `terraform/ansible-bootstrap.yaml` with `pipx ensurepath`. This ensures that binaries installed by pipx (like `ansible`) are automatically available in the `$PATH` for all interactive shells.

## 4. Verification Results
After applying the fixes, the `./scripts/verify-iter4.sh` script was run and successfully passed all **24 checks** spanning:
*   UFW status and default policies.
*   SSH hardening (Root login and password auth disabled).
*   Allowed traffic routing (LB -> Web and Web -> DB).
*   Blocked traffic isolation (DB cannot reach Web, LB cannot reach DB).

## 5. Git Merge Resolution
Resolved complex merge conflicts between `iter4-test` and `feat/iteration-4-firewall` by favoring the verified working files on `iter4-test` for:
*   `ansible/playbooks/site.yml`
*   `ansible/roles/common/tasks/main.yml`
*   `ansible/roles/nginx_lb/tasks/main.yml`
*   `scripts/verify-iter4.sh`
*   `terraform/firewall.tf`
*   `terraform/main.tf`
