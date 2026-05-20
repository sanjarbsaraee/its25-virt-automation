# Tailscale subnet router in a dedicated LXC

This document explains how we built `tailscale-gw`, an LXC container on
the Proxmox host that advertises the LAN subnet `192.168.50.0/24` to
the tailnet so team laptops reach project VMs directly.

> Background on why we moved subnet routing off the host is in
> `bugfix-session-2026-05-14.md`. The host's own Tailscale installation
> (still used for administrative SSH) is documented in
> `tailscale-on-host.md`.

## What an LXC is

A **Linux Container (LXC)** shares the host's kernel but has its own
filesystem, processes, network stack, and IP address. It is lighter
than a virtual machine because it does not simulate hardware. Unlike
Docker it runs an init system and behaves like a small Linux server.

## Why a container instead of the host

The Proxmox host originally advertised the route itself, but its
firewall and Tailscale's stateful filter held independent conntrack
tables that desynced for short-lived flows. HTTP from laptops to VMs
was dropped, SSH survived by accident. A dedicated container removes
the conflict at the root (its network namespace is separate and runs no
other firewall) and follows Tailscale's documented Proxmox pattern.
Bonus: a compromise on the gateway no longer lands on the hypervisor.

## Container specifications

| Setting | Value | Reason |
|---|---|---|
| CT ID | 100 | Any unused ID; ours is 100 |
| Template | Debian 12 standard | Matches the rest of the fleet |
| RAM | 256 MB | Tailscale + minimal Debian uses well under 100 MB |
| Swap | 256 MB | Default; the container barely uses it |
| CPU | 1 core | Subnet routing is network-bound, not CPU-bound |
| Disk | 8 GB on local-lvm | Enough for Debian + Tailscale with headroom for apt updates |
| Unprivileged | yes | Root in the container is not root on the host |
| Features | `nesting=1` | Required so the container can manage its own network namespace |
| Network | `vmbr0`, static `192.168.50.5/24`, gateway `192.168.50.1`, firewall enabled | Same LAN bridge as the VMs |
| DNS | `1.1.1.1`, `8.8.8.8` | External resolvers, independent of Proxmox host DNS |
| Autostart | enabled | Tailnet loses the route to the LAN if it stays down after host reboot |

External DNS matters: the container needs to resolve
`pkgs.tailscale.com` and `login.tailscale.com` before Tailscale itself
runs, so MagicDNS and host-side resolvers cannot be in the path.

## Build the container

Through the Proxmox web UI: **Datacenter → pve → Create CT**, or with
`pct create` from the command line. Fill in the fields from the specs
table above, including:

- **CT ID:** any unused ID (we use 100)
- **Hostname:** `tailscale-gw`
- **Template:** download Debian 12 first under **Datacenter → Storage
  → local → CT Templates** if it isn't there yet
- **Unprivileged container:** checked
- **Features → Nesting:** enabled (Options tab after creation)

Start the container and drop into a shell:

```bash
pct start 100
pct enter 100
```

Before the next steps, the container also needs access to the host's
TUN device so Tailscale can build its virtual interface. See below.

## Give the container access to /dev/net/tun

Tailscale builds a virtual network interface called a **TUN device**.
A TUN device is a software endpoint inside the kernel that looks like
a normal network card to the operating system but is actually backed
by a userspace process (in this case `tailscaled`), so packets that
the OS routes to it are handed to that process instead of being put on
a wire.

Unprivileged containers do not see `/dev/net/tun` by default because
the host's device list is hidden from them. Without it, `tailscaled`
starts but cannot create its tunnel, and the daemon fails with
`CreateTUN: operation not permitted`.

The fix is two lines in the LXC config file, edited on the **Proxmox
host** (not inside the container):

```bash
# On the Proxmox host, as root
echo 'lxc.cgroup2.devices.allow: c 10:200 rwm' >> /etc/pve/lxc/100.conf
echo 'lxc.mount.entry: /dev/net/tun dev/net/tun none bind,create=file' >> /etc/pve/lxc/100.conf

pct stop 100
pct start 100
```

What the two lines do:

- `lxc.cgroup2.devices.allow: c 10:200 rwm` allows the container to
  read, write, and mknod the character device with major number 10 and
  minor 200, which is the kernel's TUN device.
- `lxc.mount.entry: /dev/net/tun ...` bind-mounts the host's TUN
  device file into the container's `/dev/net/tun` so userspace can
  open it.

Restart is required because LXC reads the config only at container
start.

## Add the operator user

The container is filtered out of the Ansible dynamic inventory (LXC
objects lack the `proxmox_name` attribute, see
`bugfix-session-2026-05-14.md`), so the operator account is created by
hand:

```bash
adduser --disabled-password --gecos "" automation
mkdir -p /home/automation/.ssh
echo '<sanjar-public-key>' >  /home/automation/.ssh/authorized_keys
echo '<jim-public-key>'    >> /home/automation/.ssh/authorized_keys
chown -R automation:automation /home/automation/.ssh
chmod 700 /home/automation/.ssh
chmod 600 /home/automation/.ssh/authorized_keys

echo 'automation ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/automation
chmod 440 /etc/sudoers.d/automation
```

## Enable IP forwarding

The container forwards packets from the tailnet to LAN VMs, so the
kernel must allow forwarding inside the container's network namespace:

```bash
cat > /etc/sysctl.d/99-tailscale.conf <<'EOF'
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
EOF
sysctl -p /etc/sysctl.d/99-tailscale.conf
```

This is the same sysctl file the host previously used; it now lives in
the container.

## Install Tailscale

Identical procedure to `tailscale-on-host.md`, with one path difference:
the container runs Debian 12 (bookworm), the host runs Debian 13
(trixie), so the keyring URL changes:

```bash
curl -fsSL https://pkgs.tailscale.com/stable/debian/bookworm.noarmor.gpg \
  | tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null

curl -fsSL https://pkgs.tailscale.com/stable/debian/bookworm.tailscale-keyring.list \
  | tee /etc/apt/sources.list.d/tailscale.list

apt update && apt install tailscale
```

## Advertise the subnet

```bash
tailscale up --advertise-routes=192.168.50.0/24
```

Open the printed URL, sign in, approve the device. `--snat-subnet-routes`
defaults to `true`, which is Tailscale's recommended setting: incoming
traffic is source-NATed to the container's LAN IP before being
forwarded, so VMs reply to `192.168.50.5` instead of to the laptop's
tailnet IP. No iptables/MASQUERADE rules are needed because Tailscale
handles the NAT itself.

## Approve the new route, un-approve the old one

In the Tailscale admin console at
https://login.tailscale.com/admin/machines:

1. `tailscale-gw` → **Edit route settings** → toggle on
   `192.168.50.0/24` → save.
2. `pve` (the Proxmox host, `100.94.227.10`) → **Edit route settings**
   → toggle off `192.168.50.0/24` → save.

The host stays in the tailnet for administrative SSH; only its
route-advertisement is revoked.

## Update SSH config on team laptops

Add a block above the `192.168.50.*` wildcard so SSH picks the right
key when connecting directly to the gateway:

```
Host tailscale-gw 192.168.50.5
  HostName 192.168.50.5
  User automation
  IdentityFile ~/.ssh/<your>_proxmox_key
  ProxyJump <your-host-username>@100.94.227.10

Host 192.168.50.*
  ...
```

Order matters. SSH reads `~/.ssh/config` top-down and stops at the
first match, so without the specific block the wildcard would pick the
VM key, which the container does not accept.

## Verification

**Inside the container:**

```bash
tailscale status                 # gateway and peers visible
sysctl net.ipv4.ip_forward       # shows "= 1"
```

**From a laptop on the tailnet:**

```bash
ping 192.168.50.20               # reaches web-01
curl http://192.168.50.40/       # reaches lb-01 (the flow that failed before)
ssh automation@tailscale-gw      # reaches the gateway itself
```

The `curl` test is what proves the conntrack bug is gone: before the
migration it timed out while SSH worked, after the migration both
succeed.

## Maintenance notes

- **Autostart on host boot:** verify in **Options → Start at boot**, or
  `pct set 100 -onboot 1`. Without it, a host reboot leaves the tailnet
  routeless.
- **Updates:** `apt update && apt upgrade` inside the container. Test
  Tailscale major upgrades in a dev workspace first.
- **Logs:** `journalctl -u tailscaled -f` shows routes, peers, DERP
  fallbacks.
- **Do not add the container to Ansible inventory.** The inventory
  plugin's `proxmox_name is defined` guard (added in the iter 5
  follow-up PR) already excludes it. Removing the guard later would
  crash the playbook on this container.

## References

- Tailscale on Proxmox: https://tailscale.com/kb/1133/proxmox
- Subnet routers: https://tailscale.com/kb/1019/subnets
- Proxmox LXC: https://pve.proxmox.com/wiki/Linux_Container
- Migration rationale: `bugfix-session-2026-05-14.md`
- Host-side Tailscale: `tailscale-on-host.md`
