# Project Retrospective

Things the project taught us about building and validating automated
infrastructure. The notes are deliberately specific (concrete bugs,
concrete fixes) rather than abstract principles, because the
specifics are what we want to remember next time.

For the design choices that shaped the project, see
[DECISIONS](DECISIONS.md). For the current state of the
infrastructure, see the [README](../../README.md).

---

## Separation of concerns: Terraform provisions, Ansible configures

The cleanest version of the two-command flow took several rewrites to
land. An early version used `remote-exec` provisioners in Terraform
to run commands on freshly created VMs (install packages, clone the
repo, write configuration files). It looked elegant on paper.

In practice the provisioner hung waiting for sudo credentials it
never received. Worse, when the provisioner failed, Terraform's state
showed the resource as created while the VM was actually
half-configured. Subsequent `terraform apply` runs did not retry the
provisioning step (provisioners only run at creation), so the only
way out was `terraform taint` followed by destroy and recreate.

The lesson is older than this project but worth restating: Terraform
should provision (declarative, idempotent), Ansible should configure
(push-based, retriable). Mixing them breaks the failure model of
both.

---

## State management and workspace isolation

**HCP Terraform** is HashiCorp's hosted backend that stores Terraform
state remotely. Without it, two team members editing the same
infrastructure would step on each other's state files. With it, both
work against the same source of truth and lock acquisition prevents
concurrent applies.

**Self-hosted agent (`tfc-agent`)** is a worker that runs `terraform
plan` and `apply` on our network rather than on HCP's hosted runners.
Needed because HCP's cloud runners cannot reach our Proxmox host
behind Tailscale.

**Workspace isolation** lets each developer test changes against
their own VMs without risking the main environment. Three HCP
workspaces (`its25-virt-automation`, `its25-sanjar-dev`,
`its25-jim-dev`) share the same code through Terraform tags. A
workspace-aware variable map in `terraform/main.tf` assigns unique VM
IDs and IPs per workspace (offset +100 for Sanjar, +200 for Jim).

This setup worked from day one for VM-level resources. It broke at
the cluster level: Proxmox cluster security groups live in a global
namespace, so two workspaces using the same group name silently
overwrote each other's rules. We hit this on 2026-05-14 when Sanjar's
workspace had applied last and Jim's web tier could not reach the
database. The fix was to suffix role-specific group names with the
workspace identifier (see [ADR-007](DECISIONS.md)). The general
takeaway is to look for global namespaces in any provider, not just
the resources Terraform clearly owns.

---

## Reproducibility cannot be optional

The strongest signal that infrastructure is reproducible is that
`terraform destroy` followed by `terraform apply` produces the same
result. We made this a habit early and it surfaced two hidden manual
steps that would have been impossible to debug later.

**Proxmox snippets directory.** Terraform writes cloud-init snippets
into `/var/lib/vz/snippets/` on the Proxmox host. When `terraform
destroy` removed the last snippet file, Proxmox deleted the directory
itself. The next `apply` recreated the directory with default
permissions that did not match what the provider expected, so the
next snippet upload failed. The fix was a systemd path-unit on the
host that restores the correct permissions whenever the directory
changes. Documented in `docs/setup/proxmox-host.md`.

**Galaxy collections at boot.** The control node clones this repo on
first boot through cloud-init, then runs `ansible-galaxy collection
install -p ./collections -r ansible/collections/requirements.yml`.
Earlier versions left this step manual, which meant the first
playbook run after a fresh apply always failed with "collection not
found". Folding the install into cloud-init closed the gap.

The general pattern: if a step is not in code, it does not exist for
reproducibility purposes.

---

## Dynamic inventory beats static `hosts.yml`

Static inventory files break the moment Terraform changes the fleet.
We started with one, hit a desync within an hour of switching to
workspace isolation (the static file listed main-workspace IPs;
applying against `sanjar-dev` produced different IPs but Ansible
still tried the old ones).

The `community.proxmox.proxmox` plugin queries the Proxmox API at
every Ansible run and filters VMs by workspace suffix in the
hostname. Adding a VM in Terraform now means zero Ansible changes.
The plugin had two gotchas worth knowing:

- The plugin auto-prepends the API user prefix to the token name. We
  initially stored the full `terraform@pve!inventory` string in
  Infisical and got 401 errors because the plugin prepended again. The
  fix was to store just `inventory` as the token name.
- LXC objects (the `tailscale-gw` container) do not expose a
  `proxmox_name` attribute the way VMs do. Without an `is defined`
  guard, the inventory plugin crashed trying to match a non-existent
  attribute. The guard sits in
  `ansible/inventories/prod/proxmox.yml`.

---

## Runtime secret lookups beat secret files

Infisical's machine-identity flow fetches secrets at the moment
Terraform plans, Ansible runs, or Packer builds. No secret ever
touches a local file or a git commit. The control node receives only
the `Client ID` + `Client Secret` (through cloud-init at first boot),
and exchanges them for short-lived access tokens whenever it needs to
read a value.

This took noticeably longer to set up than reading from a YAML file,
but the safety properties are different. A laptop image clone, a
forgotten `git push --force` that includes a secrets file, a backup
copied to the wrong drive: none of these expose credentials when the
credentials never landed on disk in the first place.

The alternative we considered was Ansible Vault. It encrypts files at
rest but the values end up plaintext on disk during a play. Adding a
team member would also mean distributing a shared vault password
through some out-of-band channel. Infisical's per-identity access
removes both problems.

---

## Documentation drift is real

Halfway through the build, we noticed that the plan documents
(`arkitektur.md`, `iteration-5.md`) described features that were not
in the code. Not lies, just optimism: a role had been planned, the
plan was written assuming it would land, and the role got dropped
during a scope review without the plan being updated.

The discovery came from cross-checking the plan against the actual
repository contents before finalizing the documentation. The fix was
to align the plan with reality (remove descriptions of unmerged
work), not the other way around.

Two lessons:

- Verification of documentation against code is part of the work,
  not an optional QA step
- Aspirational documentation costs trust the moment a reader notices
  the gap

Both arguments are stronger when the gap is small. Letting plan and
implementation drift more than a few days makes the cleanup harder
than the work itself.
