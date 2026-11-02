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

| Item            | Value                                                  | Note                                                  |
| --------------- | ------------------------------------------------------ | ----------------------------------------------------- |
| System          | FUJITSU ESPRIMO Q920                                   | mainboard D3233-A1                                    |
| CPU             | Intel Core i5-4590T, 2.00 GHz, 4 cores, no SMT         | Haswell                                               |
| RAM             | 7.6 GiB total, **7.1 GiB used**, 561 MiB free          | an 8 GB box; KDE plus a browser is close to the limit |
| GPU             | Intel Xeon E3-1200 v3 integrated (Haswell)             | `kdn.hw.gpu.intel` is the right family                |
| NIC             | Intel I217-LM wired ethernet                           | **no Wi-Fi adapter is present**                       |
| Firmware        | UEFI 2.31 (AMI 4.654)                                  | Secure Boot **disabled**; EFI boot                    |
| OS now          | NixOS 25.05 (Warbler), generation 32, built 2025-01-08 | the old universal tree; behind current                |
| Uptime at recon | 2 days 10 h                                            | boots with a YubiKey tap                              |

The soft goal "keep Wi-Fi as a fallback" has no hardware behind it. Wired
ethernet is the only path.

## Boot and decryption: the part that must not break

The root filesystem is ZFS `pryll-main` on the LUKS mapper
`hs-e100-pryll-crypted` (`aes-xts-plain64`, 512-bit key). The encryption is
**split across two devices**:

| Device                        | Size     | Role                                                                |
| ----------------------------- | -------- | ------------------------------------------------------------------- |
| `/dev/sda` (internal SSD)     | 238.5 G  | the LUKS _data_ device, holding ZFS `pryll-main`                    |
| `/dev/sdb` (28.9 G USB flash) | 28.9 G   | holds `/boot` **and** the LUKS _header_                             |
| `/dev/sdb1`                   | 4 G vfat | `/boot`, UUID `023D-4FF3`                                           |
| `/dev/sdb2`                   | 32 M     | detached **LUKS2 header**, UUID `4f314bc3-…`, token `systemd-fido2` |

Facts:

- The LUKS header is detached onto the USB stick. `cryptsetup luksDump /dev/sda`
  fails ("not a valid LUKS device"); `cryptsetup luksDump --header /dev/sdb2
/dev/sda` shows a LUKS2 keyslot 0 with a `systemd-fido2` token.
- Unlock today is **FIDO2** (YubiKey tap). No TPM2 token is enrolled yet.
- **The owner wants TPM2-only unlock**, not YubiKey. The target is a TPM2 token in place
  of the FIDO2 one. Until the TPM token is enrolled the machine still needs a YubiKey tap;
  after enrolment a reboot is unattended.
- The 28.9 G USB stick carries `/boot` and the LUKS header, so the machine boots only while
  it is in place. It holds **no data to keep**: the owner confirmed the machine can be
  reformatted, so a lost or wiped stick costs a reinstall, not data.

## The safety net (recovery steps)

These are written from the live state. The last step, a rehearsal reboot, is a
hand-off to the owner because the machine needs a physical YubiKey tap.

1. **No header backup is required.** The owner confirmed the machine holds zero data to
   persist and may be reformatted, so a lost USB is a reinstall, not a recovery problem.
   A header backup was taken on 2026-10-30 and then removed at the owner's instruction. If a
   future build ever carries real data, redo
   `cryptsetup luksHeaderBackup /dev/sda --header /dev/sdb2 --header-backup-file <off-machine path>`.

2. **Boot the previous generation.** systemd-boot is the loader. At power-on,
   hold `Space` (or press `Esc` at the boot menu) and select
   `nixos-generation-31.conf`. Generation 32 also exposes `rescue` and `debug`
   specialisations. This is the way back if a new generation fails.

3. **Unlock.** Today: tap the FIDO2 YubiKey at the LUKS prompt (the key is plugged into the
   machine; the NanoKVM at `kvm-fa56` carries video and HID only, so a remote tap is not
   possible). The owner target is TPM2-only: enrol the TPM token once (run book phase 2b),
   then remove the FIDO2 token, after which a reboot needs no tap.

4. **Keep the USB stick in place.** Do not move `/dev/sdb`. Note it in any
   install procedure: an "install to sda" step must not reformat the stick.

## Risks carried into later phases

| Risk                                      | Why it matters                                                           |
| ----------------------------------------- | ------------------------------------------------------------------------ |
| USB carries `/boot` and the LUKS header   | lose or wipe it → a reinstall (no data to keep)                          |
| Unlock needs a tap until TPM2 is enrolled | one YubiKey hand-off to enrol the TPM token, then reboots are unattended |
| 7.6 GiB RAM, 7.1 used                     | KDE plus a browser is near the limit; keep the day-one app set small     |
| No Wi-Fi NIC                              | wired ethernet is the only network; the "Wi-Fi fallback" goal is moot    |
| Secure Boot disabled                      | a den rebuild must keep it disabled, or enrolment is a new step          |
| Generation 32 is from 2025-01-08          | goal 2 (update to current) is a large jump; do it as its own commit      |

## Open items

1. Enrol the TPM2 token and remove the FIDO2 token (owner hand-off; run book phase 2b), so a
   reboot needs no tap.
2. Confirm the USB stick vendor/health before the reinstall phase (a dead stick means reinstall).
3. SSH host certificate is absent by design on the old tree. `sshd -T` on pryll reports
   `trustedusercakeys none` and no `HostCertificate`; `/nix/persist/sys/data/etc/ssh/`
   holds only the plain keys (persisted since 2025-01-07). pryll presents a single stable
   plain ed25519 key, `SHA256:ev6CKY/DZeEUYOyTzIf9JGVpsVt+pbXxdTZMBjqIx10`, now pinned in
   `oams:~/.ssh/known_hosts`. So `ssh pryll` is stable but TOFU, not CA-verified. The CA
   host certificate arrives only with the den port (phase 2c: `ssh-host-pryll` plus the
   `ssh-ca` aspect, the same shape `brys` uses). Do not rely on CA verification for pryll
   before then.
