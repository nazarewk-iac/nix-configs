---
type: Solution
description: The kdn.certificates aspect declares the leaf option set in four classes, exposes certPath (a store path) and keyPath (the decrypted runtime path), and wires sops-nix with format = "binary".
timestamp: 2026-09-25T19:10:00+02:00
authored_by: agent
---

# Solution

## Root cause analysis

The tree held no declaration for a leaf certificate. A certificate was a file pair, not an option,
so nothing enumerated the certificates of the tree and no consumer could read a certificate path.

Two gaps followed from the first cut of this aspect:

1. `certPath` built `<repoRoot>/<directory>/<certFile>` from a hard-coded `repoRoot = ../../..`, so
   an external adopter got a store path inside the `nix-configs` store tree.
2. `keyPath` was a fixed `/run/secrets/kdn/certificates/<name>.key` string with no decrypt step, so
   nothing produced the file.

## Solution

`modules/den/aspects/certificates.nix` declares one option, `kdn.certificates.certs`, an
`attrsOf submodule` keyed by certificate name. Each leaf carries `ca`, `type`, `commonName`, `sans`,
`principals`, `directory`, `certFile`, `keyFile`, `keySource` and `minGenerationDate`, exactly as
the frozen design § 4 states.

Two derived read-only values per leaf:

- `certPath` — a store path to `<repoRoot>/<directory>/<certFile>`, safe to read at build time.
- `keyPath` — the decrypted runtime path of the private key, so no store path holds the secret.

### `repoRoot` (decision D-A, option B)

A new top-level option `kdn.certificates.repoRoot` (`nullOr path`, default `null`) names the root of
the tree that holds the certificate files. `certPath` reads it. The aspect holds **no** implicit
default, so an external adopter names their own tree root and never reads into the `nix-configs`
store tree. A declared certificate forces the value, so a missing `repoRoot` is a hard error at the
one point that reads it. An empty `kdn.certificates.certs` never forces the value.

### sops-nix wiring

The `nixos`, `darwin` and `homeManager` classes import the pinned sops-nix module and write one
`sops.secrets` entry per declared key:

- `format = "binary"` — sops writes the raw key bytes, exactly as `hack/kdn-ca-sign.sh` does.
- `sopsFile = <repoRoot>/<directory>/<keyFile>.sops` — the committed raw/binary SOPS file.
- `keyPath` reads `config.sops.secrets.<name>.path`, so the consumer reads the decrypted runtime
  path.

The sops secret name is `kdn/certificates/<name>.key`, so the default decrypted path is
`/run/secrets/kdn/certificates/<name>.key` on the NixOS and nix-darwin classes, and
`<xdg.configHome>/sops-nix/secrets/kdn/certificates/<name>.key` on the home-manager class.

**The `devenv` class fallback.** A devenv shell carries no sops-nix module and owns no system
activation, so it cannot run the sops-nix installer. Its `keyPath` is the fixed runtime path
`/run/secrets/kdn/certificates/<name>.key`, which the `kdn-certs` CLI fills with its own decrypt
primitive (`sops decrypt --output-type binary`). The aspect writes no `sops` option in that class.

The `directory` default reads `kdn.hostName`, so the aspect imports `../common/host-name.nix` by
path, as `modules/den/common/host-name.nix` documents.

The aspect signs nothing, declares no `enable` option, and is registered in `modules/den/lib.nix`.

## Verification steps

All commands exit 0:

| Command | Result |
|---|---|
| `nix build --no-eval-cache -L '.#checks.x86_64-linux.den-eval-certificates'` | 20 of 20 assertions pass |
| `nix build --no-eval-cache -L '.#checks.x86_64-linux.standalone-aspects'` | 3 of 3 assertions pass |

`checks/den-mvp/assertions/certificates.nix` holds the subjects: the empty option set on four
classes, the declared root/intermediate/leaf values, `certPath` under a store path, the missing
`repoRoot` failure, the one binary `sops.secrets` entry on `nixos`/`darwin`/`homeManager`, and the
three `keyPath` values (sops-nix on the host and home classes, the CLI fallback on `devenv`).

Every den test entity names both aspects in its own `includes`: `host-nixos`, `host-darwin`,
`users/dev`, `home`, `devenv`. No `den.default` global injection exists.

## Follow-up notes

**The `repoRoot` gap is closed.** `certPath` now resolves against the consumer's own tree root, so
an external adopter gets a path inside their own tree.

**The sops-nix import couples the aspect to the pinned input.** The aspect file takes `inputs` from
its own scope (the den library evaluation supplies `specialArgs.inputs`), exactly as
`security-secrets-sops.nix` does. The `devenv` class takes no input, so the coupling stays on the
three host and home classes.

## Amendment — the `owner` option (decision D-A)

The frozen leaf shape gained one option, `owner` (`nullOr str`, default `null`). It is a deliberate,
user-approved amendment, and it closes the key-readability gap that 006 reported: the zellij web
service is a systemd **user** service, and the default sops key file is root-only.

When a leaf names `owner`, the aspect writes `sops.secrets.<name>.owner = <owner>`. The `nixos` sops
module then derives the group from the owner (`users.<owner>.group`); the `darwin` module keeps its
`staff` default. The `homeManager` sops module declares no `owner` option, so that class ignores the
value — the aspect gates the write on a per-class `ownerSupport` flag. `mode` stays `0400`. The four
universal hosts set `owner = "kdn"`.

`checks/den-mvp/assertions/certificates.nix` covers the option default, the `nixos` owner plus
derived group, the `darwin` owner plus `staff` group, and the `homeManager` ignore. The
`den-eval-defaults` check reads the submodule default through `bareShell`.
