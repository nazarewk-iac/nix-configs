---
type: Research
description: Verified facts for the mini-PC bring-up: how to build the repo's ISO, how etra registers a host and a KVM, what the switch fabric looks like, and what the NanoKVM aspect does on a NixOS host.
task: definition.md
authored_by: agent
timestamp: 2026-10-27T20:15:00+01:00
---

# Research: the pieces this bring-up reuses

Read from this repository on 2026-10-27. Nothing here was measured on the new
machine; it does not exist yet.

## 1. The installer ISO is a flake output

`flake.nix` builds it with `nixos-generators`:

```nix
install-iso = inputs.nixos-generators.nixosGenerate {
  format = "install-iso";
  inherit system;
  modules = [ ./hosts/install-iso ];
};
```

It evaluates today:

```
$ nix eval --raw .#packages.x86_64-linux.install-iso.drvPath
/nix/store/18pxif1awj6nmk59rsy103k64j1rzbap-kdn-nixos-install-iso.iso.drv
```

So the build is `nix build .#install-iso`, and the image is
`result/iso/kdn-nixos-install-iso.iso` (`image.baseName` in
`hosts/install-iso/default.nix` forces a stable name).

Facts about that image that matter for a headless install:

- `kdn.hostName = "kdn-nixos-install-iso"`.
- `kdn.profile.machine.baseline` on, `kdn.security.disk-encryption` on.
- `kdn.security.secrets.allow = true`, so sops decryption is allowed in the
  installer.
- `kdn.networking.netbird.clients.priv.type = "ephemeral"`.
- root's `authorized_keys` is copied from user `kdn`, so SSH works on first boot
  without any extra step.
- `install-iso` forces `boot.initrd.systemd.enable = false` and
  `boot.loader.systemd-boot.enable = false` because the nixpkgs `install-iso`
  module uses its own GRUB arrangement.

## 2. How `etra` registers a host

`hosts/etra/default.nix` is the reference. The reusable parts:

```nix
kdn.profile.machine.baseline.enable = true;
kdn.profile.machine.baseline.initrd.emergency.rebootTimeout = 30;

kdn.disks.enable = true;
kdn.disks.devices."boot".path = "/dev/disk/by-id/usb-Lexar_...-0:0";
kdn.disks.luks.volumes."980pro-etra" = { targetSpec.path = "…"; uuid = "…"; headerSpec.partNum = 2; };

kdn.hw.nanokvm.enable = true;
```

The addressing half is a `lib.pipe` over a list of MAC suffixes, which builds
DHCP reservations for the KVMs:

```nix
kdn.networking.router.nets."lan".addressing."ipv4".hosts = lib.pipe
  [ "a5:8b" "e4:52" "fa:56" "4e:6e" "43:85" … ]
  [ (map lib.strings.toLower)
    (map (macSuffix: let mac = "48:da:35:6f:${macSuffix}"; … in { name = "kvm-${suffix}"; … }))
    builtins.listToAttrs ];
```

So a new KVM is one more suffix in that list. `kvm-fa56` came from exactly this
line — the `gaz` KVM is already a reservation on the LAN.

The switch fabric is also declared there: `kdn.networking.router.nets.wan` and
`.lan` are `bond` netdevs (`mode = aggregate`), and `vlan` netdevs hang off them.
`pic` is VLAN 1859, `mgmt` is 946, `drek` is 3547.

## 3. The network the SFP link must land in

From `data/network-topology.md`:

| Switch | Model | Address |
|---|---|---|
| `coll` | TP-Link SG3428X-M2 (core) | 192.168.73.207, 192.168.252.11 |
| `talt` | MikroTik CRS312-4C+8XG | 192.168.73.95, 192.168.88.1 |
| `quip` | Zyxel XGS1250-12 | 192.168.252.5 |

VLAN 946 (management) is tagged on every inter-switch link. `talt` has SFP+
cages and several hosts hang off it.

Two consequences:

1. The SFP port must be configured on the switch, in a VLAN that `etra` already
   serves. A port left in a default VLAN gets no DHCP and no route.
2. `kdn.networking.router.nets.<net>.addressing."ipv4".hosts` is where a static
   reservation belongs. A new host needs one entry, keyed on its MAC.

## 4. What `kdn.hw.nanokvm` does

`modules/den/aspects/hw-nanokvm.nix`:

- a udev rule that renames the device's USB RNDIS interface to `usb-nanokvm` and
  sets `NM_UNMANAGED`, matched on `ID_MODEL=licheervnano` and
  `ID_MODEL_ID=1009`;
- a NetworkManager profile named `usb-nanokvm` for that interface;
- the effect is that the host always reaches its KVM at a fixed link, even when
  the LAN is down.

This matters for a headless box: the KVM is the only way back in when the network
config is wrong. It should be on **before** the first risky network change.

## 5. What carries over unchanged

Everything in the Chromebook run's harness:

- the four persons (owner, overseer, orchestrator, fleet);
- the model ladder and the concurrency budget, which are properties of `brys`,
  not of the guest;
- the watch loop and its thresholds;
- the physical hand-off protocol, which for this machine is mostly "power cycle"
  and "move the USB stick", because there is no keyboard;
- the NanoKVM rules, including the HID-liveness probe: a good screenshot does not
  prove the keyboard works.

## 6. Not verified

- The machine's CPU, RAM, NIC model, and whether its SFP cage is 1G or 10G.
- Whether the machine's firmware boots this ISO with Secure Boot on.
- Whether one disk or two are present, and their `by-id` paths.
- Which switch and port the owner will use.
