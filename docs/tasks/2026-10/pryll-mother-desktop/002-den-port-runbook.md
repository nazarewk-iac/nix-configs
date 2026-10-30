---
type: Design
description: The run book for the pryll migration after the den carryover landed. Phases 2-7, the two install routes (in-place update vs fresh den reinstall), the TPM2-only unlock steps, and the owner hand-offs.
status: open
authored_by: agent
timestamp: 2026-10-30T22:40:00+01:00
---

# pryll run book: phases 2 to 7

Recon facts: [001-recon-and-safety-net.md](001-recon-and-safety-net.md).

Two owner constraints shape everything below, and they simplify the plan:

- **The machine may be reformatted. Nothing on it must be kept.** So a lost USB, a failed
  migration, or a bad update all cost a reinstall, never data. No header backup is needed.
- **Unlock is TPM2-only, not YubiKey.** Today the disk has one `systemd-fido2` token. The
  target is a TPM2 token, with the FIDO2 token removed. Enrolment is a one-time hand-off
  (it needs one unlocked boot, which today means one YubiKey tap); after that a reboot is
  unattended.

## Which install route

Because the machine is reformattable and the den host is now a full carryover
(`hosts-den/pryll`, phase 2c below), there are two routes. Route B is simpler and reaches
the end state in one move.

| Route | What | When to pick it |
|---|---|---|
| **A. In-place update** | update the old universal config, add TPM, then port to den | you want to keep the current install and roll back generation by generation |
| **B. Fresh den reinstall** (recommended) | boot the repo ISO over the NanoKVM and install `hosts-den/pryll` directly | the default: no data to keep, den is the deliverable, fastest to the goal |

Route B is the recommended path. Phase 2a is skipped; go to 2b (enrol TPM in the live ISO
or the fresh system) and phase 4.

## Phase 2a (route A only): update the current universal config

The machine is on generation 32, built 2025-01-08 (NixOS 25.05). A large jump.

```bash
nix run .#update                                             # flake update (flake-update skill)
nix build .#nixosConfigurations.pryll.config.system.build.toplevel --no-link
# owner, with a YubiKey tap at boot:
sudo nixos-rebuild switch --flake .#pryll
sudo reboot
```

Gate: the desktop returns, autologin works, the NanoKVM shows it.

## Phase 2b: unlock — TPM2 is not possible on this hardware

Measured on the live machine (2026-10-30): `/sys/class/tpm/tpm0/tpm_version_major = 1`
and `systemd-cryptenroll --tpm2-device=list` reports "No suitable TPM2 devices found".
The ESPRIMO Q920 exposes a TPM **1.2**, which `systemd-cryptenroll` cannot use (it enrols
TPM 2.0 only). So the "TPM2-only" goal cannot be met with the current firmware. Nothing was
changed on the LUKS: it still has keyslot 0 (passphrase) + keyslot 1 (the `pass` keyfile) +
a `systemd-fido2` token on keyslot 0.

Options, in order:

1. **Get a TPM 2.0.** Some ESPRIMO BIOSes can switch the TPM to 2.0, or the board takes a
   2.0 module. This is a BIOS/physical step; check it over the KVM. If the kernel then shows
   `tpm_version_major = 2`, enrol PCR 7 (systemd-cryptenroll has no `--header`; `/dev/sdb2`
   is the header device itself):

   ```bash
   pass show luks/hs-e100-pryll/keyfile | sudo systemd-cryptenroll \
     --unlock-key-file=/dev/stdin --tpm2-device=auto --tpm2-pcrs=7 /dev/sdb2
   ```

2. **Unattended boot via the `pass` keyfile on the USB stick.** The keyfile
   (`luks/hs-e100-pryll/keyfile`) already unlocks keyslot 1. Put it on the boot USB and point
   the initrd at it (`boot.initrd.luks.devices."hs-e100-pryll-crypted".keyFile`). Trade-off:
   whoever holds the USB can unlock the SSD — acceptable only because this is a home desktop
   that is reformattable.

3. **Keep the FIDO2 YubiKey tap** (works today): one tap per boot.

Do not wipe the fido2 token until option 1 or 2 is verified.

## Phase 2c: den port — DONE

`hosts-den/pryll/default.nix` is a **full carryover** of `hosts/pryll` with no
`modules/universal` reference. Its `system.build.toplevel.drvPath` instantiates. Aspects:

```
hw-basic hw-cpu-intel hw-gpu-intel hw-nanokvm hw-yubikey
locale nix-config nix-remote-builder secrets
user hm-bootstrap
profile-desktop desktop-kde stylix
disks disks-persist
ssh-ca service-rustdesk
```

What it reproduces, and the fixes made while porting:

| Old universal host | Den host |
|---|---|
| `kdn.profile.machine.desktop` | `profile-desktop` |
| `kdn.desktop.kde` | `desktop-kde` |
| `kdn.profile.user.bn` + sddm autologin | `user` + `kdn.users.bn` + `sddm.settings.Autologin` |
| `kdn.disks` LUKS with detached header | `disks` + `disks-persist` (`fs-luks-zfs` is mutually exclusive with `disks`) |
| `kdn.hw.nanokvm`, cpu/gpu intel | same aspects |
| `services.teamviewer.enable` | `services.teamviewer.enable` (RustDesk alternative below) |
| `home-manager-bn` restart hack on wallpaper | **removed**: `home-manager.users.bn.stylix.targets.kde.enable = false` |

Two den-tree pitfalls fixed inline (both are in the file's comments):

1. **Do not include `fs-luks-zfs` beside `disks`.** The tree asserts they are mutually
   exclusive. `disks` alone generates the LUKS+ZFS layout and preservation, so the
   `/var/log/journal` mount is created and no inline fileSystem was needed.
2. **`users.mutableUsers`.** `profile-baseline` sets it `false`, which trips the
   "locked out" assert (bn is not in wheel and no hash is in the repo). The host forces it
   `true`; the owner sets a password with `passwd` at install. Autologin makes it optional.

`ssh-ca` is included: add `data/.../certs.ssh-host-pryll` (principals `pryll`, the two
FQDNs) exactly like `hosts/brys/ssh-ca.nix` to give pryll a CA host certificate (the old
tree has none).

Remote support: the old host used TeamViewer, so the den host keeps
`services.teamviewer.enable = true`. RustDesk is the alternative the task prefers
(self-hostable). The `service-rustdesk` aspect is the **server** suite, not a client; a
RustDesk *client* would need a separate unattended-access setup. Decision: TeamViewer for
parity now, revisit if the licence is a problem.

## Phase 3: desktop shape

Already in the den host: KDE Plasma 6, SDDM autologin to `plasma.desktop` as `bn`, Polish
locale (via the `locale` aspect defaults), Firefox/office/PDF/image viewer/VLC (from
`profile-desktop`), TeamViewer. No LLM serving, no games, no dev toolset, no second desktop.

Confirm the wallpaper fix after activation: `systemctl --user status home-manager-bn` shows
zero restarts and `active (exited)`.

## Phase 4 (route B: fresh install over the NanoKVM)

1. `nix build .#install-iso` → attach the ISO through the NanoKVM at `kvm-fa56`.
2. Boot it. The NanoKVM carries video + HID: `ssh root@kvm-fa56...` (passwordless) and the
   MCP endpoint `https://kvm-fa56.../api/mcp` (`cube_screenshot`, `cube_type_text`, ...).
   Test one screenshot first; video was "temporarily unavailable" on 2026-10-27.
3. Install `hosts-den/pryll` to `/dev/sda` with the ESP + LUKS header on the USB stick, or
   repartition the SSD to hold them (then the USB is only the installer). The disk layout is
   declarative in `hosts-den/pryll`.
4. Gate: first boot reaches the desktop with no keyboard, autologin as bn.

## Phase 5: autonomy

`system.autoUpgrade` with `allowReboot = false` (do not reboot the user under her) and a
`nix.gc` window. A failed update leaves the previous generation bootable. With TPM2-only
unlock, an unattended reboot works; verify over the KVM that a boot after an update lands on
the desktop with no intervention, and that remote support reconnects.

## Phase 6: backup

The machine may be wiped, so "backup" means the owner's documents and photos, not the
system. A local USB disk, plugged in permanently, holding a snapshot of `/home/bn`.
Demonstrate one restore from the KVM alone; record the steps.

## Phase 7: evaluation

Fill the shared fleet evaluation
([../gaz-den-workstation/003-fleet-evaluation/definition.md](../gaz-den-workstation/003-fleet-evaluation/definition.md))
with this run's numbers, or mark it "not observed". The Pi harness is the pane-per-sub-agent
layout in `llm:pryll:harness`; per-turn data is in each run's session JSONL.

## Owner-only hand-offs

1. **Unlock path** (phase 2b): the TPM is 1.2, so choose — enable a TPM 2.0 in BIOS (then I
   enrol it), or accept a keyfile-on-USB for unattended boot, or keep the YubiKey tap.
2. **Decide TeamViewer vs RustDesk**, and provide the TeamViewer credential through the
   existing secret mechanism if TeamViewer stays.
3. **brys disk pruning**: `/var/lib/kdn/llms/models` is 98% full (41 G free) and
   `qwen3-next-80b` (~40 G) cannot fit. Choose models to drop.
4. The usability defaults: Polish / `pl` / Europe-Warsaw / light / autologin / Firefox /
   USB backup / no peripherals. Say if any is wrong.
