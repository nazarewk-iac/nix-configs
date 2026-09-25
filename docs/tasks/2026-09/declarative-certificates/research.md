---
type: Research
description: Tool comparison, the den enumeration model, the SOPS binary-secret model and the SSH-certificate gap that support the declarative-certificates design.
task: definition.md
authored_by: agent
timestamp: 2026-09-25T17:29:39+02:00
---

# Declarative certificates — research

This file synthesizes the findings behind [design.md](design.md). The frozen spec at
`/tmp/opencode/cert-design-spec.md` holds the decisions. This file records the evidence and the
open questions.

## 1 — Tool choice

The tool must cover four certificate kinds, run offline, and keep a committable configuration with
separable secrets. The candidates:

| Tool | TLS server | TLS client | SSH user | SSH host | Offline | Config | Verdict |
|---|---|---|---|---|---|---|---|
| **smallstep** (`step-cli` 0.30.6, `step-ca` 0.30.2) | yes | yes | yes | yes | yes | `config/ca.json`, Apache-2.0 | **chosen** |
| Cloudflare Origin CA | yes | no | no | no | no | zone-bound | TLS-only fallback |
| `cfssl` | yes | yes | no | no | yes | JSON | rejected — no SSH |
| `mkcert` | yes | no | no | no | yes | none | rejected — no SSH, no CA |
| Vault | yes | yes | yes | yes | no | online | rejected — online, BUSL-1.1 |

**Verdict: smallstep.** It is the only candidate that covers all four kinds. It runs fully offline
through `step certificate create --ca … --ca-key …` and `step ca certificate --offline`. It keeps a
committable JSON configuration (`config/ca.json`) with the secrets separable. Both packages are in
the repo's pinned nixpkgs: `step-cli` 0.30.6 and `step-ca` 0.30.2, both Apache-2.0. Measured with
`nix eval --raw 'nixpkgs#step-cli.version'` and `nix eval --raw 'nixpkgs#step-ca.version'`.

**Cloudflare is a TLS-only fallback.** Origin CA is zone-bound, it accepts no IP subjectAltName, and
it has no SSH path. Do not design an SSH path through Cloudflare.

## 2 — The den enumeration model

The CLI must find every certificate declaration in a flake. den exposes four output shapes, plus
three legacy shapes.

| Output | Shape | Cert read |
|---|---|---|
| `den.hosts` | one host set per system | the host name list |
| `denConfigurations.<host>` | a nix-darwin or a NixOS system | `.config.kdn.certificates` |
| `denHomeConfigurations.<name>` | a standalone home-manager configuration | `.config.kdn.certificates` |
| `denDevenvShells.<name>` | a devenv shell | `.kdn.certificates` |

The `denDevenvShells` read is one level shorter. `den.devenv.mkShell` returns `.config` alone
(`modules/den/classes/devenv.nix:75`), so the shell has no outer `.config`. The host and home reads
need the `.config` prefix; the shell read does not.

The three legacy outputs stay in the walk: `nixosConfigurations`, `darwinConfigurations` and
`homeConfigurations`. Each one reads `.config.kdn.certificates`.

### devenv sub-profiles

The root `devenv.nix` is not a flake output. Its sub-profiles live under `config.profiles.hostname`
and `config.profiles.user`. The CLI reads them through the devenv `evalModules` entry
(`<devenv>/src/modules/top-level.nix`) or through `devenv eval`.

### Missing-option tolerance

Every read must tolerate a target that declares no certificate option. Use
`builtins.attrByPath [ "kdn" "certificates" ] { } cfg` semantics at every read. A missing option is
an empty set, never an error. This rule keeps the CLI usable on a flake that adopts the tree
partly.

### Explicit includes, not `den.default`

`den.default.includes` injects an aspect into the entity kinds `host`, `user` and `home`. It is
declared at `<den>/modules/aspects/defaults.nix:15-19`. It exists only on the `flakeModule` route
(`modules/den/flake-module.nix`), not on `denLib`. A bare `den.lib.aspects.resolve` never reads
`den.default` (`checks/den-mvp/devenv/default.nix:8-11`).

The design deliberately does **not** use `den.default`. Every den host, user, home and standalone
devenv shell names the aspect in its own `includes` (or `denLib.imports { aspects = [ … ]; }`). An
explicit include shows which entity needs which aspect. One global line hides that.

**UNVERIFIED:** whether a host-derived devenv shell reaches an aspect that the host names. The
standalone shells declare no entity, so the design names `kdn.certificates` and `kdn.ca-dag` in each
standalone devenv shell by hand. Record this as a risk until a measurement settles it.

### Universal-host augmentation

The old-tree hosts oams, brys, etra and moss do not migrate to den in this task. They adopt one
aspect at a time through the den library route:

```nix
imports = [ (denLib.imports { class = "nixos"; aspects = [ "certificates" ]; }) ];
```

`denLib.imports` returns a list of plain modules. The list drops straight into a universal host's
`imports = [ … ];`. The library route (`modules/den/lib.nix`) exists for exactly this case and needs
no den adoption. Sub-task `000-universal-augmentation` verifies the mechanism and documents the
caveats: option-declaration clashes, `den.default` absent on the library route, and the
`standalone-aspects` constraints. Sub-task `006-zellij-migration` depends on it.

## 3 — The SOPS binary-secret model

The private key of a leaf is a raw/binary SOPS file. The model has five parts.

### Raw/binary JSON

A raw SOPS file holds the plaintext bytes, not a YAML or JSON document. `sops decrypt --output-type
binary` writes the original bytes. `sops encrypt --output-type binary` reads the original bytes.
`hack/kdn-ca-sign.sh:58` and `:71-74` already use this form for the CA key and the leaf key.

### CA key custody

The CA private key is SOPS-sourced, exactly like `data/ca/ca.key.sops` today. It is encrypted to
YubiKey touch identities, so a real CA operation needs a physical touch. The `kdn-certs` CLI prompts
for the touch when it signs with such a CA. More decryption candidates can join later for
automation. The recipient set is a `.sops.yaml` concern, not a code concern.

A **test CA** may use an unattended key. Its recipient is a test identity, so the test suite signs
with no YubiKey. The test CA lives outside `data/`, under `checks/` or a temporary directory.

### Per-host SSH age identity

`.sops.yaml` defines one age recipient per host from its SSH host key. The comment records the
conversion: `ssh-to-age </etc/ssh/ssh_host_ed25519_key.pub`. Each host key is an anchor such as
`&ssh-oams`. A leaf key for one host encrypts to that host's identity alone, plus the admin touch
keys. A shared rule would grant every listed host access to every other host's key. The CA key is
not a leaf key, so it does not use the per-host pattern.

### First-match `creation_rules`

SOPS applies the first `creation_rules` entry whose `path_regex` matches the file path. The
per-host rules sit above the generic rules in `.sops.yaml`. The existing zellij rules show the
shape:

```yaml
- path_regex: 'hosts/oams/certs/zellij\.key\.sops$'
  key_groups:
    - age:
        - *ssh-oams
        - *yk-oams-touch
        - *yk-brys-touch
        - *yk-pton-touch
```

A new leaf key must add its own rule above the generic `.*\.key\.sops` rule. A rule below a
matching generic rule never fires.

### The oneshot plus `LoadCredential` pattern

A service must not read a store path that holds a secret. Two patterns exist in the tree:

1. A systemd oneshot decrypts the SOPS file into `/run/secrets`, sets the owner and mode 0400, and
   `RemainAfterExit`. The zellij web aspect uses this pattern at
   `modules/den/aspects/zellij.nix:396-419`.
2. A service reads the decrypted path through `LoadCredential`, so the unit reads it at run time
   and no store path holds it. The iperf3 aspect uses this pattern at
   `modules/den/aspects/service-iperf3.nix:157-160`.

The declarative design uses the first pattern for the leaf key. The aspect exposes `keyPath` as the
decrypted runtime path.

## 4 — The SSH-certificate gap

The tree holds no SSH certificate today. `TrustedUserCAKeys`, `HostCertificate`, `@cert-authority`
and `CertificateFile` appear in no module. A search over `modules/` finds no hit.

The SSH CA serves two classes of consumer. Interactive logins use short-lived user certificates with
principals, consumed by `ssh` and the `kdn-*` tools. Automation (CI, remote builders and agents)
cannot manage long-lived `authorized_keys` files, so it consumes certificates too. Different
validity per class is allowed.

Two server settings and two client settings close the gap:

| Side | Setting | Job |
|---|---|---|
| Server | `services.openssh.settings.TrustedUserCAKeys` | the SSH CA public key; every user certificate it signs logs in |
| Server | `services.openssh.settings.HostCertificate` | the host certificate the server presents |
| Client | an `@cert-authority` line in `known_hosts` | trust every host certificate the CA signs |
| Client | `CertificateFile` in the ssh drop-in | the user certificate the client presents |

The client drop-in directory is `~/.ssh/config.d/`. `program-ssh-client` includes it through
`programs.ssh.includes = [ "~/.ssh/config.d/*.config" ]` (`modules/den/aspects/program-ssh-client.nix:24`).
`ssh-access` writes `40-kdn-ssh-access.config` into the same directory
(`modules/den/aspects/ssh-access.nix:182`). The SSH CA file uses the number `50-`, so it sorts after
the `40-` file.

`kdn-ssh-access` is orthogonal. It picks routes and identities. It does not decide trust. Do not
couple the two aspects.

**UNVERIFIED:** whether nix-darwin declares `services.openssh.settings`. The `nixos` class sets the
two settings with no doubt. The `darwin` class may not expose the same option. Verify this before
the `darwin` work starts.

## 5 — The current manual flow

`hack/kdn-ca-sign.sh` is the whole automation today. It does five steps:

1. Decrypt `data/ca/ca.key.sops` to a temporary file (`hack/kdn-ca-sign.sh:58`).
2. Generate an EC P-256 leaf key with `openssl ecparam`.
3. Build a CSR with `openssl req`, with the subjectAltName extension.
4. Sign the CSR with `openssl x509 -req`, against `data/ca/ca.pub` and the CA key.
5. Verify the leaf against `data/ca/ca.pub` and SOPS-encrypt the leaf key.

The CA private key needs a YubiKey touch, so the script stays manual. The declarative design keeps
the YubiKey touch for the CA key. The `kdn-certs` CLI prompts for the touch, and it automates the
leaf work. A test CA with an unattended key lets the test suite sign with no YubiKey.

`data/ca/ca.md` records the same flow in prose. It states the storage rule that the design keeps:
the public leaf certificate is committed plain, and the private leaf key is SOPS-encrypted
raw/binary next to it.
