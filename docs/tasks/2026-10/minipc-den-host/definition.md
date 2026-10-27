---
type: Task
description: Bring up a new x86 mini-PC as a den NixOS host in the manner of etra, installed from this repo's own ISO over USB-SFP networking, driven and evaluated by the supervised local-LLM fleet.
status: open
authored_by: agent
timestamp: 2026-10-27T20:10:00+01:00
---

# A new x86 mini-PC, built by the supervised fleet

This task **mostly covers the purposes** of
[../gaz-den-workstation/definition.md](../gaz-den-workstation/definition.md).
That one converts a Chromebook and is blocked on a hardware purchase (a
SuzyQable, or the CR50 battery-disconnect procedure). This one has no such
blocker, so it goes first and produces the two results the Chromebook task was
written for:

1. a host moved to the den convention, with the repository's own disk layout;
2. the measured answer to "how do we drive work with the local fleet most
   efficiently".

The harness, the model ladder, the watch loop and the physical hand-off protocol
are **not repeated here**. They live in
[../gaz-den-workstation/design.md](../gaz-den-workstation/design.md) and apply
unchanged. The evaluation is
[../gaz-den-workstation/003-fleet-evaluation/definition.md](../gaz-den-workstation/003-fleet-evaluation/definition.md),
and it measures whichever run happens first. The verified fleet, KVM and tooling
facts are in
[../gaz-den-workstation/research.md](../gaz-den-workstation/research.md).

## Premises the owner has already set

The owner does these **before** the task starts, so the session does not begin
blind:

| Item | State |
|---|---|
| The machine is plugged in and powered. | owner |
| The machine has a **host name**. | owner picks it; the task uses `<name>` as a placeholder |
| A NanoKVM is plugged into it (HDMI and USB). | owner |
| The machine boots this repo's ISO from USB. | `nix build .#install-iso` → `result/iso/kdn-nixos-install-iso.iso` |
| The machine is plugged into a switch over an **SFP** link. | owner |
| The switch port is configured for the intended VLAN. | owner, or the agent with switch access |

Everything else follows the same rules as the Chromebook run: the fleet does the
work, the overseer supervises, the owner has the hands, nothing is pushed.

## What "in the manner of etra" means

`hosts/etra/default.nix` is the reference for a host that is wired into the
network as a first-class citizen. The parts to copy:

| Concern | How etra does it |
|---|---|
| Profile | `kdn.profile.machine.baseline` with an explicit initrd emergency timeout |
| Disk | `kdn.disks` with `luks.volumes."<disk>-<host>"` and the boot device by `by-id` path |
| Impersonation of a normal node | SSH access through the `kdn-*` dispatcher, SSH host certificate from the CA |
| Out-of-band | `kdn.hw.nanokvm.enable = true` |
| Address | a static IPv4 in its VLAN, a DHCP reservation keyed on the MAC, and a DNS name |
| Switch links | `kdn.networking.router.nets.*` with a `bond` netdev and VLAN children |

Not every part is needed on a non-router. Whether this machine takes a **router**
role is an open question; the default is "no", because a router role rewrites the
default route, DNS and firewall for the whole site.

## Phases

Each phase ends with a commit and one `.worklog.md` line, as in the Chromebook
task.

| Phase | Work | Gate |
|---|---|---|
| 0 | Harness up: KVM reachable, screenshots and keys proven, Zellij session, orchestrator spawned, watch loop running. | a test delegation to a fast alias returns |
| 1 | Recon from the live ISO over the KVM: `dmidecode`, `lspci`, `lsblk`, `ip -br link`, `ethtool` on the SFP NIC, RAM, firmware mode. | a committed hardware profile for `<name>` |
| 2 | Name and identity: host name, `networking.hostId`, the SSH host key, the SOPS recipients, the DHCP reservation and DNS name. | the values are recorded and committed |
| 3 | `hosts-den/<name>` skeleton: class, aspects, tmpfs root, no bootloader yet. | `nix eval .#denConfigurations.<name>` returns a system |
| 4 | Disk: `kdn.disks` layout for the real devices, ESP included. | the layout evaluates and the installer finds the disk |
| 5 | Install over the KVM, first boot, SSH reachable through the dispatcher. | `<name>` answers SSH with a valid host certificate |
| 6 | Profile parity: the roles the machine will actually serve, nothing more. | `nixos-rebuild switch` on the machine |
| 7 | Evaluation write-up. | the shared evaluation is done |

## Requirements

### Hard

1. `hosts-den/<name>/default.nix`, with `den.hosts.x86_64-linux.<name>.class = "nixos"`. Never in `nixosConfigurations`.
2. The disk layout is `kdn.disks` (tmpfs root, ZFS on LUKS with a detached header) plus `fs-zfs`. Never both `disks` and `fs-luks-zfs`.
3. The machine is reachable as `<name>` through the existing SSH-CA path, not by a raw address.
4. The NanoKVM is registered like every other one: a DHCP reservation on its MAC and a `kvm-xxxx` name.
5. The SFP link is declarative, in the repo, not a hand-edited `/etc` file on the machine.
6. Nothing in the run pushes to a remote.
7. No secret in the repo, a log, or a screenshot.

### Soft

- Prefer an existing aspect. A host-specific block must be short.
- Do not give the machine a role it will not serve. A mini-PC that only runs a
  test does not need a desktop, a gaming profile, or a router role.
- Keep `hosts/install-iso` untouched. It is a build input, not a host.

## Differences from the Chromebook run

| Topic | Chromebook (`gaz`) | This machine |
|---|---|---|
| Firmware | MrChromebox UEFI Full ROM, needs CR50 write-protect work | stock UEFI, nothing to flash |
| Boot media | USB installer after a firmware change | USB installer, directly |
| Installer | any | this repo's `.#install-iso` |
| Input device | laptop keyboard and panel | none: the KVM is the only console |
| Network | Wi-Fi likely, then LAN | SFP into a switch, static VLAN address |
| Reversibility | flashing is one-way in practice | nothing irreversible before the disk write |
| Blocker | a SuzyQable purchase or a case opening | none |

The last row is the reason this task goes first.

## Open questions

- The host name, and therefore every derived value. Placeholder is `<name>` until
  the owner states it.
- Does it take a router role, or a plain host role? Plain is the default.
- Which switch and which port, and which VLAN does that port carry? The SFP link
  must land in a VLAN that the router already serves, or the machine is isolated.
- Is the SFP NIC a single port or a pair? A pair would follow etra's `bond` with
  `mode = aggregate`; a single port is a plain `ethernet` netdev.
- Is there a second disk, and is the root pool one disk or a mirror?
- Does the machine need `zramSwap` at 50 percent, as `brys` and `etra` do?

## Acceptance

- `<name>` is a den host in `hosts-den/`, and its layout is `kdn.disks` with ZFS
  impermanence and a tmpfs root.
- It boots from its internal disk, with no USB.
- It answers SSH as `<name>` under the CA.
- Its KVM is registered and usable by the next agent.
- The shared fleet evaluation has real numbers from this run, or is marked
  "not observed" per table.
