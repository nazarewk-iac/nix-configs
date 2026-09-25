---
type: Solution
description: The kdn.ca-dag aspect declares the CA graph as data in four classes, with no generation, no system trust and no enable option.
timestamp: 2026-09-25T18:40:00+02:00
authored_by: agent
---

# Solution

## Root cause analysis

The tree held no declarative layer for certificate authorities. `kdn.ca` trusts a CA as a system CA
and nothing enumerated the CA graph.

## Solution

`modules/den/aspects/ca-dag.nix` declares one option, `kdn.ca-dag.cas`, an `attrsOf submodule` keyed
by CA name. Each node carries `type`, `parent`, `commonName`, `directory`, `certFile`, `keyFile`,
`keySource`, `provisioner`, `ssh` and `minGenerationDate`, exactly as the frozen design § 3 states.

It emits no configuration. An empty `kdn.ca-dag.cas` is the no-op. It declares no `enable` option.
It is registered in `modules/den/lib.nix` next to `ca`.

The option set is identical in all four classes, so one module serves each of `nixos`, `darwin`,
`homeManager` and `devenv`.

## Verification steps

All commands exit 0:

| Command | Result |
|---|---|
| `nix build --no-eval-cache -L '.#checks.x86_64-linux.den-eval-certificates'` | pass |
| `nix build --no-eval-cache -L '.#checks.x86_64-linux.standalone-aspects'` | pass |
| `nix build --no-eval-cache -L '.#checks.x86_64-linux.den-eval-coverage'` | pass |
| `nix build --no-eval-cache -L '.#checks.x86_64-linux.den-eval-guards'` | pass |
| `nix build --no-eval-cache -L '.#checks.x86_64-linux.bundle-core'` | pass |

`checks/den-mvp/assertions/certificates.nix` holds one bare-consumer subject per class plus a
declared root and intermediate, and the `instantiatedBy` row for `ca-dag`.
`checks/den-mvp/tests.nix` gains `ca-dag` in the `den-eval-guards` registry list.

## Follow-up notes

The DAG sort, the `parent`-names-no-CA error and the cycle error belong to the CLI (004). This
aspect declares the data only.
