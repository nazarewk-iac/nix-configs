---
type: Research
description: Phase 0b and phase 1 findings for pryll. Read-only recon over SSH, the hardware profile, the same-machine verdict, and the boot-decryption safety net that the migration must not break.
status: open
authored_by: agent
timestamp: 2026-10-30T21:40:00+01:00
---

# pryll phase 0b + 1: recon and the safety net

Read-only. No change was made on the machine. The machine is in service for the
owner's mother, so every finding below is also a constraint on the later phases.

## Same machine: yes

`hosts/pryll` identifies the disk as `ata-HS-SSD-E100_256G_30023586951`. The
live machine reports `sda` as `HS-SSD-E100 256G`, SATA, serial `30023586951`.
The values match. The disk identity in `hosts/pryll` is correct for this node.

## Hardware profile

| Item | Value | Note |
|---|---|---|
| System | FUJITSU ESPRIMO Q920 | mainboard D3233-A1 |
| CPU | Intel Core i5-4590T, 2.00 GHz, 4 cores, no SMT | Haswell |
| RAM | 7.6 GiB total, **7.1 GiB used**, 561 MiB free | an 8 GB box; KDE plus a browser is close to the limit |
| GPU | Intel Xeon E3-1200 v3 integrated (Haswell) | `kdn.hw.gpu.intel` is the right family |
| NIC | Intel I217-LM wired ethernet | **no Wi-Fi adapter is present** |
| Firmware | UEFI 2.31 (AMI 4.654) | Secure Boot **disabled**; EFI boot |
| OS now | NixOS 25.05 (Warbler), generation 32, built 2025-01-08 | the old universal tree; behind current |
| Uptime at recon | 2 days 10 h | boots with a YubiKey tap |

The soft goal "keep Wi-Fi as a fallback" has no hardware behind it. Wired
ethernet is the only path.

## Boot and decryption: the part that must not break

The root filesystem is ZFS `pryll-main` on the LUKS mapper
`hs-e100-pryll-crypted` (`aes-xts-plain64`, 512-bit key). The encryption is
**split across two devices**:

| Device | Size | Role |
|---|---|---|
| `/dev/sda` (internal SSD) | 238.5 G | the LUKS *data* device, holding ZFS `pryll-main` |
| `/dev/sdb` (28.9 G USB flash) | 28.9 G | holds `/boot` **and** the LUKS *header* |
| `/dev/sdb1` | 4 G vfat | `/boot`, UUID `023D-4FF3` |
| `/dev/sdb2` | 32 M | detached **LUKS2 header**, UUID `4f314bc3-…`, token `systemd-fido2` |

Facts:

- The LUKS header is detached onto the USB stick. `cryptsetup luksDump /dev/sda`
  fails ("not a valid LUKS device"); `cryptsetup luksDump --header /dev/sdb2
  /dev/sda` shows a LUKS2 keyslot 0 with a `systemd-fido2` token.
- Unlock is **FIDO2** (YubiKey tap). No TPM2 token is enrolled yet. That is
  goal 1 of this task: add TPM beside the FIDO2 token.
- **The machine cannot boot without that USB flash.** It carries `/boot` and the
  only copy of the LUKS header. A lost, dead, or overwritten stick makes the
  internal SSD unrecoverable. Backing up the header is mandatory before any
  destructive phase.

## The safety net (recovery steps)

These are written from the live state. The last step, a rehearsal reboot, is a
hand-off to the owner because the machine needs a physical YubiKey tap.

1. **Back up the detached header now.** As root on pryll:

   ```
   cryptsetup luksHeaderBackup --header /dev/sdb2 \
     --header-backup-file /some/safe/off-machine/pryll-luks-header.img
   ```

   Keep it off the machine and out of the repo; it holds keyslot material. This
   is the one action that turns "lost USB" from fatal into recoverable.

2. **Boot the previous generation.** systemd-boot is the loader. At power-on,
   hold `Space` (or press `Esc` at the boot menu) and select
   `nixos-generation-31.conf`. Generation 32 also exposes `rescue` and `debug`
   specialisations. This is the way back if a new generation fails.

3. **Unlock.** Insert and tap the FIDO2 YubiKey when the LUKS prompt waits. The
   key is plugged into the machine; the NanoKVM at `kvm-fa56` carries the video
   and the HID, so a remote tap is not possible. Every reboot is a hand-off.

4. **Keep the USB stick in place.** Do not move `/dev/sdb`. Note it in any
   install procedure: an "install to sda" step must not reformat the stick.

## Risks carried into later phases

| Risk | Why it matters |
|---|---|
| USB carries `/boot` and the LUKS header | lose or wipe it → unrecoverable SSD; back it up first |
| Unlock needs a physical YubiKey tap | every reboot is an owner hand-off; the run cannot self-reboot over the KVM |
| 7.6 GiB RAM, 7.1 used | KDE plus a browser is near the limit; keep the day-one app set small |
| No Wi-Fi NIC | wired ethernet is the only network; the "Wi-Fi fallback" goal is moot |
| Secure Boot disabled | a den rebuild must keep it disabled, or enrolment is a new step |
| Generation 32 is from 2025-01-08 | goal 2 (update to current) is a large jump; do it as its own commit |

## Open items

1. Rehearse a reboot to generation 31 and back (owner hand-off, needs the YubiKey).
2. Back up the detached LUKS header to an off-machine path (owner picks the place).
3. Confirm the USB stick vendor/health before the reinstall phase.
