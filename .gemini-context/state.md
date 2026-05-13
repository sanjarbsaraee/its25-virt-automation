# Session State

## Current Objective
Finalize Iteration 4 (Dual-layer firewall and hardening) and prepare for Iteration 5 (Monitoring and Advanced Hardening).

## Active Overrides
None.

## Next Steps
1. [x] Merge the `iter4-test` branch into `main` (Already completed).
2. [/] Start execution of the Iteration 5 plan (`iteration-5-plan.md`).

## Resolved Issues and Mistakes
*   **Proxmox Firewall Silence:** Discovered that the `bpg/proxmox` provider requires `enabled = true` inside `rule` blocks in security groups, otherwise they default to false.
*   **Ansible Timeout on Slow Hosts:** Small VMs under heavy I/O or during service restarts occasionally hit the default 10s timeout. Fixed by increasing it to 30s in `ansible.cfg`.
*   **Cloud-Init PATH Resolution:** Discovered that non-login shells didn't see pipx binaries. Fixed by using `pipx ensurepath` in the bootstrap script.
