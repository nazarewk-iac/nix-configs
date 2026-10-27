---
type: Research
description: Verified facts on age-plugin-tpm, its sops-nix integration, alternatives, and whether a TPM-sealed identity survives a reinstall.
task: definition.md
authored_by: agent
timestamp: 2026-10-27T17:38:00+01:00
---

# Research: TPM-derived age keys for sops-nix

All facts below were checked on 2026-10-27 against the pinned nixpkgs (`nixpkgs#age-plugin-tpm`
reports version `1.0.1`, `meta.description` = "TPM 2.0 plugin for age (This software is experimental,
use it at your own risk)"), the repo's own age aspect
(`modules/den/aspects/security-secrets-age.nix`), and the upstream plugin sources.

## 1. `age-plugin-tpm` — what it is and what it is not

- **Repo:** https://github.com/Foxboron/age-plugin-tpm — by Foxboron, the
  `systemd-cryptenroll`/`systemd-measured-boot` author. MIT. Active.
- **nixpkgs attribute:** `pkgs.age-plugin-tpm`, version `1.0.1`. Linux only
  (`x86_64-linux`, `aarch64-linux`).
- **Mechanism** (`plugin/plugin.go`, `plugin/identity.go`, `plugin/tpm.go`): it derives a
  deterministic primary key with `TPM2_CreatePrimary` under the storage root key (persistent handle
  `0x81000001`, falling back to a transient SRK). It then creates the identity key with
  `TPM2_Create` beneath that primary. The identity file (`AGE-PLUGIN-TPM-...`) holds the
  TPM-wrapped private blob and the public part. The private key never leaves the TPM.
- **No PCR binding.** The key template uses `FixedTPM`, `FixedParent`, `SensitiveDataOrigin`,
  `UserWithAuth`, `Decrypt`. There is no `AuthPolicy`. Upstream issue #21 "Sealing keys with PCRs" is
  still open. The maintainer says a `Reseal` API is a precondition.
- **Device:** opens `/dev/tpmrm0` (kernel resource manager). No `tpm2-abrmd` daemon is needed.
- **Optional PIN** (`--pin` / `AGE_TPM_PIN`). For unattended boot we do **not** set a PIN: a PIN
  prompt blocks the boot, and an env-var PIN is readable from `/proc/$PID/environ`.
- **Status:** README says "experimental, use at your own risk". Not yet standardized (pending
  `p256tag` in C2SP). The maintainer calls it "low on my priority list until `p256tag` is
  standardized".

**Consequence for this fleet.** The plugin gives hardware-bound, unattended, PIN-less decryption. Its
"TPM" protects against *offline key extraction* (a stolen disk), not against a live attacker at the
console. For boot-time sops decryption that is the right threat model; the live-attacker case is the
job of full disk encryption.

## 2. sops-nix integration — supported today, one friction point

Checked against `Mic92/sops-nix` (`modules/sops/default.nix`) and this repo's pin.

- **`sops.age.plugins`** (`listOf package`, default `[]`) — "List of plugins to use for sops
  decryption." Wired in two places: `systemd.services.sops-install-secrets.path = cfg.age.plugins;`
  and the unit `PATH` via `with-environment.nix`. A plugin on this list is on `PATH` when
  `sops-install-secrets` runs, so sops invokes `age-plugin-tpm` automatically.
- **`sops.age.keyFile`** (`pathNotInStore`, default `null`) — path to the age identity file. **It must
  not be in the Nix store.** This is the one friction point (see below).
- **Assertion:** at least one key source must be set: `keyFile != null || sshKeyPaths != [] || gnupg`.
  Setting `keyFile` to the TPM identity satisfies it.
- **No built-in TPM option.** TPM works through the generic age-plugin path.
- **Origin of the plugin support:** PR #781 "feat: add age plugin support, take 2", merged
  2026-01-10. It lists `age-plugin-tpm` among supported plugins.
- **The store restriction:** issue #840 "Allow age.keyFile to be in Nix store" is specifically about
  `age-plugin-tpm`. It is still open. The maintainer's workaround (PR #534) copies the identity to a
  runtime path at boot:
  ```
  cp -r ${./tpm-identity.txt} /run/age-keys.txt
  chmod 700 /run/age-keys.txt
  ```
  then `sops.age.keyFile = "/run/age-keys.txt";`.

### Fit with this repo's age aspect

`modules/den/aspects/security-secrets-age.nix` already has the exact shape a TPM identity needs:

- `kdn.security.secrets.age.plugins` (line 63) forwards to `sops.age.plugins` (line 205) and to the
  unit `PATH` (line 265).
- `kdn.security.secrets.age.keyFile` (line 72) becomes `sops.age.keyFile` (line 238);
  `sops.age.generateKey = false` and `sops.age.sshKeyPaths = []` are already set (lines 235-237).
- `kdn.security.secrets.age.genScripts` (line 82) plus `service.preStart` (line 143) already build one
  script per key source and merge every generated identity into `keyFile` with `sort -u`
  (lines 147-158). The built-in SSH-host-key generator is at lines 122-138.

So a TPM identity is one more `plugins` entry plus one more `genScripts` entry, not a new mechanism.
The `hw-yubikey` aspect shows the pattern: it publishes `kdn.hw.yubikey.agePlugins` and
`kdn.hw.yubikey.ageGenScripts` for another aspect to consume
(`modules/den/aspects/hw-yubikey.nix:112-160`).

## 3. Alternatives — what can actually feed sops-nix

| Approach | Feeds sops-nix? | Verdict |
|---|---|---|
| **`age-plugin-tpm`** | **Yes**, directly (`sops.age.plugins` + `keyFile`). | The only native path. Unattended, no PCR brittleness. Recommended. |
| `systemd-creds` | Indirect: `systemd-creds encrypt --with-key=tpm2` holds an age key, `decrypt` writes it at boot. | Works but needs scripting; sops-nix has no hook. Default `host+tpm2` also binds a disk file (`/var/lib/systemd/credential.secret`). More moving parts. |
| `systemd-cryptenroll --tpm2` | **No.** It enrolls a LUKS keyslot; it does not yield a plaintext key for sops. | Right tool for FDE, wrong tool for sops. |
| `clevis` + `tang` | **No** (tang is network-bound; clevis tpm2 is LUKS-oriented). | Out of scope; heavier. |
| TPM SSH key (`ssh-tpm-agent`, `ssh-tpm-keygen`) | Indirect at best. The public half converts to an age recipient, but age cannot drive an ssh-agent to decrypt. Foxboron states this in #33. | Not viable for unattended decrypt. |

**NixOS requirements:** `security.tpm2.enable = true;` (creates `/dev/tpmrm0` udev rules and the
`tss` group) and a kernel module (`tpm_tis` or the platform variant, e.g. `tpm_crb`) loaded before
`sops-install-secrets`. No `tpm2-abrmd`.

## 4. Does the TPM identity survive a reinstall?

The authoritative source is Foxboron's answer in age-plugin-tpm issue #33 (comment 4667906156).

- **The TPM chip** is on the motherboard and persists physically. ✅
- **The owner-hierarchy seed** (the source of the deterministic primary) lives in TPM NVRAM, not on
  disk. Wiping or reformatting the disk, wiping `/nix`, or reinstalling NixOS does not touch it. ✅
- **The identity file** (the wrapped blob) is a **file on disk**, not TPM NVRAM. If a reinstall loses
  that file, decryption is gone even though the TPM and its seed survive. ⚠️
- **`tpm2_clear`** clears the owner hierarchy. After that, the wrapping primary changes and the old
  blob can no longer be unwrapped. A NixOS reinstall does **not** automatically `tpm2_clear`, so a
  clean reinstall that leaves the hierarchy intact and restores the same blob may still decrypt.
  Any `tpm2_clear`, owner-hierarchy re-init, or firmware change that resets it = permanent loss of
  that blob. There is no "pull the key back out".
- **PCRs are irrelevant** because there is no PCR binding. A reinstall, a `nixos-rebuild`, a
  bootloader/shim/kernel update or a Secure Boot re-enrollment does **not** break unsealing. This is
  both the benefit (no re-seal churn) and the security tradeoff (no measurement verification). If
  PCR binding (#21) were ever added, every boot-chain change would require a re-seal.

**Durability recipe.**

1. Back up the `AGE-PLUGIN-TPM-...` identity blob **off the host**. It is safe at rest: only the
   matching TPM can use it.
2. Do **not** run `tpm2_clear` on an enrolled machine.
3. Keep at least one human-held (YubiKey/SSH-key) recipient on every `.sops.yaml` rule, so a lost TPM
   is always recoverable. The public `age1tpm...` recipient can be regenerated from the identity with
   `age-plugin-tpm -y`, but not without the blob.

**Answer to "set it once, survive reinstalls?"** — Set the TPM once and it survives a reinstall *only
if* (a) you keep the identity blob backed up off the host and restore it, and (b) nobody clears the
TPM owner hierarchy. The TPM hardware and its seed are stable across reinstalls; the disk file and the
hierarchy state are the fragile parts. Treat the blob like any other key backup, and keep the YubiKey
recipients as the recovery path.

## 5. Practical recommendation

Make the TPM identity the **primary** unattended decryptor and drop `pcscd` from the boot path on
every host with a TPM 2.0. Keep YubiKey recipients as break-glass. Minimal per-host NixOS shape:

```nix
security.tpm2.enable = true;
boot.kernelModules = [ "tpm_tis" ];

sops.age.generateKey = false;
sops.age.sshKeyPaths = [ ];
sops.age.keyFile = "/var/lib/sops-nix/key.txt";
sops.age.plugins = [ pkgs.age-plugin-tpm ];

systemd.tmpfiles.rules = [
  "d /var/lib/sops-nix 0700 root root -"
  # mirror the persistent identity to the runtime path sops reads
  "C+ /var/lib/sops-nix/key.txt 0600 root root - /persist/sops/tpm-identity.txt"
];

systemd.services.sops-install-secrets.after = [ "dev-tpmrm0.device" ];
systemd.services.sops-install-secrets.wants  = [ "dev-tpmrm0.device" ];
```

Enrollment, once per host, as root and interactive:

```sh
age-plugin-tpm --generate -o /persist/sops/tpm-identity.txt   # no --pin, unattended
age-plugin-tpm -y /persist/sops/tpm-identity.txt              # prints the age1tpm... recipient
# add the recipient to the host's key_groups in .sops.yaml, then re-encrypt the files
```

In this repo the equivalent is: add `age-plugin-tpm` through `kdn.security.secrets.age.plugins`, add
a generator through `kdn.security.secrets.age.genScripts` (or seed `keyFile` directly), and gate the
`hw-yubikey` PCSC edge on a new "required for boot" option that defaults to `false` once a TPM
identity is present.

## Sources

- `gh:Foxboron/age-plugin-tpm` — `plugin/plugin.go`, `plugin/identity.go`, `plugin/tpm.go`; README;
  issue #21 (PCR sealing, open); issue #33 (security model and reinstall answer).
- nixpkgs: `pkgs/by-name/so/sops/package.nix` (`withAgePlugins`); attr `age-plugin-tpm` @ `1.0.1`
  (verified by `nix eval nixpkgs#age-plugin-tpm.version`).
- `gh:Mic92/sops-nix` — `modules/sops/default.nix` (`age.plugins`, `age.keyFile`, `pathNotInStore`);
  `with-environment.nix`; PR #781 (age plugin support); issue #840 (`age-plugin-tpm` store
  restriction, open); PR #534 (maintainer workaround).
- NixOS `nixos/modules/security/tpm2.nix` (`security.tpm2.enable`, `/dev/tpmrm0` udev).
- systemd `systemd-creds(1)`: `--with-key=host|tpm2|host+tpm2|auto-initrd`, `--tpm2-pcrs=`.
- This repo: `modules/den/aspects/security-secrets-age.nix:63,72,82,122-160,205,235-238,265`;
  `modules/den/aspects/hw-yubikey.nix:112-160,227-234`.
