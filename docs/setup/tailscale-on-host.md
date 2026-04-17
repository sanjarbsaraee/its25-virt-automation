# Tailscale on the Proxmox host

This document explains how we installed Tailscale on our Proxmox VE host, and why. The goal is to give both team members remote access to the Proxmox web interface without exposing port 8006 to the internet.

## Overview

Tailscale is a mesh VPN built on WireGuard. Every device running the Tailscale client becomes a peer with a stable address in the 100.64.0.0/10 range. Traffic flows directly between peers when NAT traversal succeeds, and falls back to DERP relay servers operated by Tailscale when it does not. All traffic is end-to-end encrypted with WireGuard, including when relayed, since DERP servers only forward already encrypted packets.

A coordination service operated by Tailscale handles authentication and helps peers discover each other. It does not see plaintext traffic.

```
              Tailscale coordination and DERP relays
              (authentication, peer discovery, fallback)
                      ^           ^           ^
                      |           |           |
              [Sanjar laptop] [Proxmox host] [Jim laptop]
                      ^           ^           ^
                      |           |           |
                      +---direct WireGuard tunnels---+
```

## Why Tailscale

We considered three options.

Classic port forwarding would expose the Proxmox web UI directly to the internet, which conflicts with the defense-in-depth principle the project builds on.

A self-hosted WireGuard gateway, the pattern used in Project 6 of the course, would require manual key management and at least one open UDP port on our home routers. The gateway itself becomes a single point of failure for remote access.

Tailscale solves both problems. NAT traversal is automatic, keys are managed by the coordination service, and there is no central gateway for data traffic. The trade-off is trust in Tailscale's hosted infrastructure, which we address in Known limitations below.

## Why install on the host, not in a VM

Proxmox serves its web UI on port 8006 of the host itself, not of any guest VM. A VM has its own network stack, so installing Tailscale inside one would expose the VM but not the management interface.

Port forwarding from a VM to the host would create a circular dependency. If the VM failed, the only way to restart it would be the web UI that we could no longer reach.

A later iteration will also install Tailscale inside the Ansible control VM. That serves a different purpose, giving the control node a stable address for SSH from team laptops, and complements rather than replaces the installation on the host.

## Prerequisites

- Proxmox VE 9.1 installed and reachable on the LAN at 192.168.50.197
- Root SSH access from at least one team laptop
- A Tailscale account on the free Personal plan, which covers up to 6 users with unlimited user devices and up to 50 tagged resources

## Installation

All steps are executed as root on the Proxmox host. Root access is an inherited limitation of the current setup and is tracked as a known issue in the project knowledge base.

**Step 1. Add Tailscale's signing key.**

```bash
curl -fsSL https://pkgs.tailscale.com/stable/debian/trixie.noarmor.gpg \
  | tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
```

The command downloads Tailscale's public signing key in binary format and writes it to `/usr/share/keyrings/`. This location is the modern convention for third-party apt keys, since it allows the key to be scoped to a specific repository rather than trusted for all repositories. Installing the key before adding the repository ensures that apt can verify package signatures on the very first update.

Silent success indicates the file was written without error.

**Step 2. Add the Tailscale repository.**

```bash
curl -fsSL https://pkgs.tailscale.com/stable/debian/trixie.tailscale-keyring.list \
  | tee /etc/apt/sources.list.d/tailscale.list
```

The file that is written contains one line:

```
deb [signed-by=/usr/share/keyrings/tailscale-archive-keyring.gpg] https://pkgs.tailscale.com/stable/debian trixie main
```

The `signed-by` attribute pairs this repository with the specific key file from step 1. Apt will only accept packages from this repository if they are signed by that exact key, which limits the blast radius if any other key on the system is ever compromised.

**Step 3. Update apt's package cache.**

```bash
apt update
```

Apt fetches the package catalogs from all configured repositories, including the new Tailscale repository. A successful run shows `Get:` lines for Tailscale's `InRelease` and `Packages` files. Any `401 Unauthorized` errors from Proxmox enterprise repositories are unrelated and are tracked separately as a known limitation.

**Step 4. Install the Tailscale package.**

```bash
apt install tailscale
```

Apt resolves dependencies, downloads the package, verifies its signature against the key installed in step 1, and installs it. During installation, systemd is instructed to enable the `tailscaled` service at boot, indicated by a line similar to:

```
Created symlink '/etc/systemd/system/multi-user.target.wants/tailscaled.service' → '/usr/lib/systemd/system/tailscaled.service'.
```

This means the service starts automatically on every reboot.

**Step 5. Verify the service is running.**

```bash
systemctl status tailscaled
```

Expected output includes `Active: active (running)` and `Status: "Needs login:"`. The daemon is running but has no tailnet configuration, which is the correct intermediate state before authentication.

**Step 6. Authenticate and join the tailnet.**

```bash
tailscale up
```

The command prints an authentication URL of the form `https://login.tailscale.com/a/<token>`. Open the URL in a browser, sign in with the account that will own the tailnet, and approve the device. The terminal prints `Success.` once the authentication flow starts, not when it completes. Completion happens in the background once the browser step is done.

## Verification

**Check the assigned tailnet IP.**

```bash
tailscale ip -4
```

Returns a single IPv4 address in the 100.64.0.0/10 range. This is the stable address the host keeps across reboots and network changes. Other team members use this address to reach the Proxmox web UI.

**List tailnet membership.**

```bash
tailscale status
```

Returns a table of devices currently in the tailnet. Each row shows the tailnet IP, hostname, owner account, operating system, and connection state. After a fresh installation only the Proxmox host is present.

**Access the web UI over Tailscale.**

From a laptop that has also joined the same tailnet, open `https://<proxmox-tailnet-ip>:8006` in a browser. The Proxmox login page loads the same way it does over the LAN, but is now reachable from any network the laptop connects to.

## Adding team members

Tailscale uses a multi-user tailnet model. Each user signs in with their own identity provider account and appears as a separate user in the admin console. Devices belong to users, not to the tailnet as a whole.

**Process used for onboarding the second team member:**

1. The tailnet owner opens the Tailscale admin console at `https://login.tailscale.com/admin/users` and clicks "Invite external users". The owner enters the new user's email address and sends the invite.
2. The invited user receives an email with a link. Opening the link takes them to Tailscale's sign in page. They authenticate with the same identity provider the tailnet uses, in our case GitHub. This places them in the tailnet but their devices are not yet connected.
3. The invited user installs the Tailscale client on their laptop, available at `https://tailscale.com/download`, and signs in with the same GitHub account.
4. Because the tailnet has approval required enabled, the new user's device appears in the admin console in a pending state. The owner approves the device from Machines, and the device becomes active.
5. The new user verifies access by opening `https://<proxmox-tailnet-ip>:8006` in a browser. The Proxmox web UI loads, confirming the connection is working end-to-end.

**Why approval required is enabled:**

The default configuration requires an admin to approve new devices before they can reach other nodes in the tailnet. Even if an invite link leaks, the device cannot access project infrastructure without a second explicit action from the tailnet owner. This is a small but real additional layer of defense.

## Known limitations and future work

This section will discuss the trust boundary introduced by Tailscale's hosted coordination plane, and the option of running Headscale as a self-hosted alternative. It will also cover MagicDNS, ACL configuration, and automatic certificate provisioning for the web UI.

## References

- Tailscale on a Proxmox host: https://tailscale.com/kb/1133/proxmox
- Connection types and DERP fallback: https://tailscale.com/kb/1257/connection-types
- How Tailscale works: https://tailscale.com/blog/how-tailscale-works
- Tailscale pricing v4 (April 2026): https://tailscale.com/blog/pricing-v4
