# Proxmox host setup

This document describes how the Proxmox VE host that runs the project infrastructure is installed and configured. It focuses on the parts of the setup that are project-specific. General Proxmox installation and day-to-day administration are covered by the official Proxmox wiki and are linked at the end.

## Overview

The host is a small-form-factor AMD machine that runs Proxmox VE 9.1, a Type 1 hypervisor based on Debian 13 Trixie. Once the host is set up, Terraform provisions VMs on it and Ansible configures those VMs. Remote access to the web UI on port 8006 is handled by Tailscale, which is a separate setup document.

The steps below take a new machine from bare metal to a point where Tailscale can be installed and the first VM can be provisioned. The sequence matters. Hardware virtualization has to be enabled before the installer runs. The repository switch has to happen before any `apt upgrade`, otherwise the upgrade will fail on authentication errors against the default enterprise repositories. The host user and SSH configuration are tightened before the Proxmox API is exposed beyond the LAN.

## Prerequisites

- Hardware with AMD-V or Intel VT-x support, enabled in BIOS or UEFI firmware. On this project the machine uses AMD, where the relevant setting is called SVM Mode.
- A wired LAN connection to the same network as the administrative laptops, with a free IP address that can be assigned statically during the installer.
- A USB drive of at least 2 GB, and the official Proxmox VE 9.1 ISO written to it. The Proxmox documentation covers writing the ISO on Windows, macOS, and Linux.
- A monitor, keyboard, and mouse for the initial installation. These are only needed during install and for first boot, since everything after that happens over the network.
- A modern browser on the laptop for the first web UI login.

## Step 1. Enable hardware virtualization in firmware

Hypervisors rely on CPU extensions that are often disabled by default on consumer hardware. AMD calls this extension SVM Mode, and Intel calls it VT-x. Without it the kernel can still boot, but Proxmox cannot start any virtual machine. The symptom shows up as a KVM error the first time you try to create a VM, not during install, which makes it easy to miss until it is too late.

On Windows machines that do not expose a boot-device selector at POST, the cleanest way to reach firmware settings is to request them explicitly from the running operating system. Open PowerShell as Administrator and run:

```powershell
shutdown /r /fw /t 0
```

This tells Windows to reboot directly into the firmware interface. In the firmware menu, find the CPU configuration section and enable SVM Mode on AMD or VT-x on Intel. Save and exit.

If the firmware is locked and does not expose SVM as a visible setting, the vendor may require a separate unlock utility. That detail is vendor-specific and is recorded in the internal setup notes rather than here.

## Step 2. Install Proxmox VE

The general installation procedure is covered well in the Proxmox wiki, so this section only records the choices that are specific to this project.

Boot from the USB drive. When the installer asks for the target disk, select the internal NVMe SSD. On our hardware this appears as `/dev/nvme0n1`. The installer writes an LVM-thin layout by default, which is appropriate for a host that will run VMs.

The network step asks for a management interface, a hostname, an IP address, a gateway, and a DNS server. Choose values that match the local network. The project host uses a static IP in the 192.168.50.0/24 range with the home router as both gateway and DNS. A fully qualified hostname such as `pve.matrix.local` is useful even on a network without a real DNS zone, because Proxmox writes it into its own internal certificates.

The installer also asks for a root password and an administrator email address. Set a strong password. Neither is committed to the repository.

After the installer reboots the machine, the shell login prompt appears on the local console. The installation itself is complete at this point, but most of the setup is still ahead.

## Step 3. First login over the web UI

From a laptop on the same LAN, open `https://<host-ip>:8006` in a browser. On this project that is `https://192.168.50.197:8006`. The browser will warn about the self-signed certificate, which is expected. Proxmox uses a self-signed certificate until a real one is provisioned, and replacing it is out of scope for this document.

Log in as `root` with the password set during installation. The realm is `Linux PAM standard authentication`. A successful login shows the Proxmox dashboard with one node in the tree. At this point the host is reachable but not yet safe to use.

## Step 4. Switch from enterprise to no-subscription repositories

A fresh Proxmox VE install enables the enterprise package repositories by default. The enterprise repositories require a paid Proxmox subscription, and without one, `apt update` returns `401 Unauthorized` for every Proxmox repository on every run. No package upgrades can be installed until this is fixed. The community-supported no-subscription repositories contain the same packages without the subscription requirement, and are the correct choice for a student project.

The configuration uses the deb822 format that Proxmox VE 9 ships with. Two files need to change.

Replace `/etc/apt/sources.list.d/pve-enterprise.sources` with:

```
Types: deb
URIs: http://download.proxmox.com/debian/pve
Suites: trixie
Components: pve-no-subscription
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
```

Replace `/etc/apt/sources.list.d/ceph.sources` with:

```
Types: deb
URIs: http://download.proxmox.com/debian/ceph-squid
Suites: trixie
Components: no-subscription
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
```

Both files point to the same signing key, which ships with Proxmox and does not need to be installed separately. Note that the Ceph repository uses `no-subscription` as the component name, while the PVE repository uses `pve-no-subscription`. This is a small naming inconsistency in upstream and is easy to miss.

Verify that the change worked:

```bash
apt update
```

A successful run shows `Get:` lines for both `pve-no-subscription` and `no-subscription` and no `401 Unauthorized` errors from any Proxmox repository. If the output still shows 401 errors, one of the two files is still pointing at the enterprise URL. Re-check the `URIs:` line in both.

## Step 5. Apply queued package upgrades

The repository switch in step 4 exposes a large set of package upgrades that were previously invisible behind the `401 Unauthorized` errors. The system needs to converge on the current no-subscription state before anything else is built on top.

The recommended sequence is to inspect first, upgrade second, reboot third, and verify last. Each stage has a clear purpose, and skipping stages is the common source of misconfigured hosts.

Inspect what is pending.

```bash
apt list --upgradable
```

The output is a long list of paginated entries. Press `q` to exit the pager when done reading. On a fresh host after step 4, the list contains around 130 packages and is a mix of standard Debian base packages and Proxmox-specific packages with names prefixed `pve-`, `libpve-`, `proxmox-`, and `ceph-`.

Run the upgrade.

```bash
apt upgrade
```

Read the summary before pressing `Y`. Pay attention to three things. The number of packages being upgraded should match what `apt list --upgradable` showed. A new kernel package such as `proxmox-kernel-6.17.13-2-pve-signed` in the dependencies means a reboot is required afterward. Any package in the `Not upgrading:` list is held back deliberately, typically because a dependency transition prevents a straight upgrade.

When `apt-listchanges` pauses to display news from a specific package, read the notice if relevant, then press `q` to continue. This happens most commonly for `amd64-microcode` releases that carry CPU security bulletins.

If the `Not upgrading:` list contains ZFS packages and this host uses ZFS, resolve the held-back upgrades separately with `apt full-upgrade`. The `full-upgrade` variant is willing to install and remove packages to satisfy dependency transitions, which is what ZFS library version bumps often require. Read the summary of proposed removals carefully before confirming. If this host does not use ZFS, the held-back packages can be left as they are or removed entirely. On this project the host runs on LVM-thin and the ZFS packages were upgraded for consistency only.

Reboot.

```bash
reboot
```

The SSH session terminates as the host shuts down, typically with a message like `Connection to <host> closed by remote host`. This is expected. The machine needs 30 to 60 seconds to come back. Attempt to reconnect after roughly a minute.

Verify the upgrade took effect.

```bash
uname -r
pveversion
apt list --upgradable
```

The kernel version returned by `uname -r` should match the new kernel that was installed. `pveversion` should report the expected Proxmox version, for example `pve-manager/9.1.7` or later. `apt list --upgradable` should return an empty list, which confirms the system is fully converged.

Note: the message `No /etc/kernel/proxmox-boot-uuids found, skipping ESP sync` may appear during the upgrade on hosts installed on LVM-thin rather than ZFS with a systemd-boot setup. It is informational, not an error, and can be ignored on such hosts.

## Step 6. Create a sudo user and disable root SSH

Daily administration should not happen as `root`. A mistyped command as root can destroy the whole host, including every VM on it. Requiring an explicit `sudo` step gives the administrator a moment to reconsider before running a privileged command. Separate accounts per team member also make the audit log meaningful, since each action is attributed to a named user rather than to the shared `root` account.

Disabling root over SSH removes the most commonly attacked account from any brute-force attempt over the network, and aligns with standard SSH hardening recommendations from CIS Benchmarks and the `devsec.hardening` Ansible collection.

The sequence is deliberate. Create the new user, grant sudo, install the `sudo` package if it is missing, verify the new path works end to end, and only then disable root login. Reversing the order risks being locked out of the host.

Create the user.

```bash
adduser <username>
```

The command prompts for a password and a few optional fields (full name, phone numbers). All fields except the password are optional and can be left blank. The password should be generated locally in a password manager, not shared through any channel that logs or retains input.

Add the user to the `sudo` group.

```bash
usermod -aG sudo <username>
```

The `-a` flag appends to the existing group list. Without it, the command would replace the user's groups entirely, which would remove membership of the default user group and break expected behavior. Verify with:

```bash
groups <username>
```

The output should list `sudo` among the groups.

Install the `sudo` package if it is not already present. Proxmox does not install `sudo` by default on a fresh host, since the assumption is that administration happens as root. Installing it makes the new user actually able to elevate privileges.

```bash
apt install sudo
```

Test the new path before touching SSH configuration. From an administrator laptop, open a new terminal and confirm that SSH login and sudo both work:

```bash
ssh <username>@<host-ip>
sudo whoami
```

The prompt should end in `$` after login, signaling that the shell is running as a regular user rather than as root. `sudo whoami` should prompt for the user's own password, not the root password, and return `root`. A second `sudo` command within fifteen minutes reuses the authenticated session and does not prompt again.

Back up the SSH configuration before editing it. A backup makes it possible to roll back quickly if the new configuration has a typo that prevents the service from restarting.

```bash
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup-<date>
```

Inspect the current setting for root login, so the before and after state is explicit.

```bash
grep -i permitrootlogin /etc/ssh/sshd_config
```

On a default Proxmox install this returns `PermitRootLogin yes` as the active setting, along with a commented example line.

Change the setting.

```bash
sed -i 's/^PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
```

The `^` anchor ensures that the replacement matches only the active setting at the start of a line, not the commented example that also contains the phrase. Verify the change with the same grep command.

Validate the configuration syntactically before reloading the service. A syntax error at this stage would prevent SSH from restarting and would lock the host, which is why the check happens first.

```bash
sshd -t
```

No output means the configuration is valid. Any output indicates an error that must be fixed before proceeding.

Reload the service. `reload` signals the running SSH daemon to re-read its configuration without terminating existing sessions, which preserves the current administrator's root session as a safety net.

```bash
systemctl reload ssh
```

Verify the service is active and picked up the change:

```bash
systemctl status ssh
```

Look for `Active: active (running)` and a recent `Reloaded ssh.service` entry in the log. Press `q` to exit the pager.

Verify the new state from an administrator laptop. Open a fresh terminal and attempt a root login. The expected result is that authentication fails regardless of the password supplied:

```
ssh root@<host-ip>
root@<host-ip>'s password:
Permission denied, please try again.
```

Press `Ctrl+C` to cancel. Then confirm that the named user can still log in:

```bash
ssh <username>@<host-ip>
```

Once the named user login is verified, the root session that was kept open as a safety net can be closed. The host is now reachable only through named accounts, with `sudo` as the elevation path.

## Verification

After all steps above have been completed, the following should all be true.

The web UI at `https://<host-ip>:8006` loads and accepts the administrator login.

`apt update` on the host returns success with no 401 errors from any Proxmox repository. `apt list --upgradable` returns an empty list, confirming that the queued packages have been applied.

`ssh <sudo-user>@<host-ip>` succeeds from an administrator laptop, using key-based authentication. `sudo -i` works inside that session.

`ssh root@<host-ip>` is refused by the host with `Permission denied`, confirming that root login over SSH is disabled.

A final cross-check that hardware virtualization is really enabled:

```bash
grep -c -E 'svm|vmx' /proc/cpuinfo
```

A non-zero output confirms that the CPU exposes the virtualization extension and that the kernel sees it. A zero means the firmware setting is still off, and no VM will be able to start.

## Known limitations

The host runs on consumer hardware rather than in a datacenter, and the network uplink goes through a home router. The project knowledge base tracks the full list of known limitations, including the trust boundary introduced by Tailscale's hosted coordination plane.

This setup leaves the Proxmox web UI on a self-signed certificate. Replacing it with a real certificate, through ACME or an internal certificate authority, is out of scope for the initial setup and is planned for a later iteration.

## Next steps

Once the host is configured, the project continues with Tailscale for remote access to the web UI. That procedure is documented separately in [Tailscale on the Proxmox host](tailscale-on-host.md).

## References

- Proxmox VE installation: https://pve.proxmox.com/wiki/Installation
- Proxmox VE package repositories: https://pve.proxmox.com/wiki/Package_Repositories
- Proxmox VE network configuration: https://pve.proxmox.com/wiki/Network_Configuration
- Debian deb822 source format: https://manpages.debian.org/bookworm/apt/sources.list.5.en.html
