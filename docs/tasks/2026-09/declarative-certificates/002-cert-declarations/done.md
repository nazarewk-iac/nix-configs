---
type: Solution
description: The kdn.certificates aspect declares the leaf option set in four classes and exposes certPath (a store path) and keyPath (the decrypted runtime path).
timestamp: 2026-09-25T18:40:00+02:00
authored_by: agent
---

# Solution

## Root cause analysis

The tree held no declaration for a leaf certificate. A certificate was a file pair, not an option,
so nothing enumerated the certificates of the tree and no consumer could read a certificate path.

## Solution

`modules/den/aspects/certificates.nix` declares one option, `kdn.certificates.certs`, an
`attrsOf submodule` keyed by certificate name. Each leaf carries `ca`, `type`, `commonName`, `sans`,
`principals`, `directory`, `certFile`, `keyFile`, `keySource` and `minGenerationDate`, exactly as
the frozen design § 4 states.

Two derived read-only values per leaf:

- `certPath` — a store path to `<directory>/<certFile>`, safe to read at build time.
- `keyPath` — `/run/secrets/kdn/certificates/<name>.key`, the decrypted runtime path, so no store
  path holds the secret.

The `directory` default reads `kdn.hostName`, so the aspect imports `../common/host-name.nix` by
path, as `modules/den/common/host-name.nix` documents.

The aspect signs nothing, declares no `enable` option, and is registered in `modules/den/lib.nix`.

## Verification steps

All commands exit 0:

| Command | Result |
|---|---|
| `nix build --no-eval-cache -L '.#checks.x86_64-linux.den-eval-certificates'` | 12 of 12 assertions pass |
| `nix build --no-eval-cache -L '.#checks.x86_64-linux.standalone-aspects'` | pass |
| `nix build --no-eval-cache -L '.#checks.x86_64-linux.den-eval-coverage'` | pass |
| `nix build --no-eval-cache -L '.#checks.x86_64-linux.den-eval-guards'` | pass |
| `nix build --no-eval-cache -L '.#checks.x86_64-linux.bundle-core'` | pass |
| `nix build --no-eval-cache -L '.#checks.x86_64-linux.den-eval-devenv-cli'` | pass |
| `nix build --no-eval-cache -L '.#checks.x86_64-linux.den-eval-routes'` | pass |

Every den test entity names both aspects in its own `includes`: `host-nixos`, `host-darwin`,
`users/dev`, `home`, `devenv`. No `den.default` global injection exists.

## Follow-up notes

**The consumer repo root is an open gap.** `certPath` builds `<repoRoot>/<directory>/<certFile>`
from `repoRoot = ../../..`, which is **this repository's** root. That is correct for the in-repo
consumers (006). An external adopter who imports `denModules.certificates` gets a store path inside
the `nix-configs` store tree, not their own tree. The frozen option set holds no repo-root option,
and `kdnConfig.self` is forbidden on the aspect route. This is reported as a decision for the task
owner.
