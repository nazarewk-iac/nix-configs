---
type: Task
description: Derive an unattended age identity from the host TPM, so boot-time sops decryption needs no PCSC smart card, no YubiKey, and no SSH host key yet.
status: open
authored_by: agent
timestamp: 2026-10-27T17:38:00+01:00
---

# TPM-derived age keys for sops decryption

## Context

On 2026-10-27 host `brys` refused SSH on port 22 on every interface. The cause was a systemd
ordering cycle:

```
sysinit.target -> sops-install-secrets.service -> pcscd.socket -> sysinit.target
```

`modules/den/aspects/hw-yubikey.nix` adds `sops-install-secrets` `After=`/`Requires=pcscd.socket`,
because the only age identities the host can build unattended come from the `age-plugin-yubikey`
plugin. A default `pcscd.socket` is `After=sysinit.target` (its `DefaultDependencies` are on), and
sops-nix runs `sops-install-secrets.service` `Before=sysinit.target`. systemd broke the cycle by
deleting the `sops-install-secrets.service/start` job. No secret was decrypted, `kdn-secrets.target`
never fired, and `sshd` (which `Requires` that target through the `ssh-ca` aspect) never started. The
box was alive (Caddy served 80/443) but unreachable.

The immediate cycle fix belongs in this same change set. This task is the next step: remove the
*mandatory* dependence on PCSC and on a smart card at all.

Today the unattended identities are:

1. `age-plugin-yubikey` via `services.pcscd` (`modules/den/aspects/hw-yubikey.nix:227-234`), and
2. the SSH host key converted with `ssh-to-age`
   (`modules/den/aspects/security-secrets-age.nix:122-138`).

Both have a cost. The YubiKey path drags in `pcscd` and the ordering cycle. The SSH host key path
needs the host key to exist *and* to be a recipient of the encrypted file. Neither is a property of
the hardware itself.

The TPM 2.0 on the motherboard is such a property. It can hold an age identity that decrypts with no
user present, no smart card daemon, and no SSH key. See [research.md](research.md) for the verified
facts, the plugin caveats and the reinstall behaviour.

## Goals

- A TPM-backed age identity is the **primary** unattended decryptor on every host that has a TPM 2.0.
- `services.pcscd` and the `sops-install-secrets -> pcscd.socket` edge become **optional**. A host
  with a TPM must boot with no PCSC ordering at all. A YubiKey stays available as a break-glass
  recipient, but it no longer gates the boot.
- The identity file lives **outside the Nix store** (the sops-nix `pathNotInStore` rule blocks
  `age-plugin-tpm` identities) and survives reboots on persistent storage.
- A person runs one documented command per host to enroll it, then adds the printed `age1tpm...`
  recipient to the host's `.sops.yaml` creation rule.

## Non-goals

- No PCR binding. `age-plugin-tpm` binds to the TPM owner hierarchy, not to measurements
  (research § 1, § 4). This is a deliberate trade: no re-seal after every bootloader or kernel
  change, but no protection against a live attacker at the console. That threat is covered by full
  disk encryption, not by sops.
- No replacement of the YubiKey for the CA keys (`data/ca/*.key.sops`). Those keep touch-required
  custody; they are never decrypted by a host at boot.
- No `systemd-creds` or `clevis` plumbing. Research § 3 shows both are more moving parts for the same
  result; `age-plugin-tpm` is the native sops-nix path.

## Proposed approach

A new den aspect, or a branch inside `security-secrets-age.nix`, that:

1. Enables `security.tpm2.enable = true` and ensures `tpm_tis` (or the platform module) loads so
   `/dev/tpmrm0` exists before `sops-install-secrets` runs.
2. Adds `pkgs.age-plugin-tpm` to `kdn.security.secrets.age.plugins` (the aspect already forwards
   this to `sops.age.plugins` and to the unit `PATH`, `security-secrets-age.nix:205,265`).
3. Seeds the identity onto persistent storage outside the store, using the existing
   `genScripts`/`preStart` contract (`security-secrets-age.nix:143-160`). The identity is either
   generated once at enrollment or read from a persistent path mirrored into `/run`.
4. Orders `sops-install-secrets` after `dev-tpmrm0.device`, `Wants` that device.
5. Makes the `hw-yubikey` PCSC edge conditional on a *new* option (for example
   `kdn.hw.yubikey.requiredForBoot`, default `false` once a TPM identity exists), so the
   `After=pcscd.socket`/`Requires=pcscd.socket` pair is written only when a host still needs the
   YubiKey to decrypt at boot.
6. Documents the enrollment command, the `.sops.yaml` recipient, the recovery path, and the reinstall
   behaviour in a new section of `docs/` (likely `docs/declarative-certificates.md` or a new
   `docs/sops-age-tpm.md`).

## Acceptance

- On a TPM host, a cold boot decrypts the secrets with `pcscd` absent from the boot transaction
  (`systemctl list-dependencies` on `sops-install-secrets` shows no `pcscd.socket` edge).
- `sshd` starts on a cold boot without a manual start, on a host where the only unattended identity
  is the TPM.
- Removing the TPM identity file from the persistent path is the only way to lose unattended boot,
  and the YubiKey recipients still let an admin recover.
- The setup document states, with the research citations, that the TPM chip and its owner seed
  survive a reinstall but the identity blob does not (if it is not backed up), and that a
  `tpm2_clear` makes the old blob unusable.

## Open questions

- **Identity storage path.** `/persist/sops/` (repo convention) versus `/var/lib/sops-nix/tpm/`.
  Check what the fleet's persistence layout expects on `brys`, `etra`, `oams`, `anji`.
- **One-member key groups.** After a TPM recipient joins a rule, is it acceptable to drop the
  touch-YubiKeys from the *non-CA* rules, or keep them as break-glass? Research recommends keeping at
  least one human-held recipient on every rule.
- **Plugin maturity.** `age-plugin-tpm` is labelled experimental. Decide whether to gate it behind an
  opt-in option per host, or enable it fleet-wide once the first host proves it.
- **Enrollment on an already-installed host.** Does `age-plugin-tpm --generate` need a reboot to pick
  up the new rule, or only a `nixos-rebuild switch` plus a rewrite of the `.sops` files?
