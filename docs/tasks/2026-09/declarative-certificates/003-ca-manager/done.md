---
type: Solution
description: The kdn.ca-manager aspect includes kdn.ca-dag and adds the kdn-certs CLI to a devenv shell, with an offline enterTest.
timestamp: 2026-09-25T19:15:00+02:00
authored_by: agent
---

# Solution

## Root cause analysis

The tree held no devenv shell that carried the `kdn-certs` CLI and the CA graph. The CA DAG aspect
declares data only, and the CLI package had no consumer. So no shell could run a sign operation.

## Solution

`modules/den/aspects/ca-manager.nix` is the `kdn.ca-manager` aspect. It has the `devenv` class only.

- It includes `kdn.ca-dag`, so the shell carries the CA graph option set.
- It adds the `kdn-certs` package to `config.packages` through a relative path literal
  (`pkgs.callPackage ../../../packages/kdn-certs { }`), so it needs no overlay and no `pkgs.kdn.*`
  entry.
- It adds no service, no system trust and no file.
- It declares no `enable` option. An empty CA DAG is the no-op.

The smallstep server lifecycle lives in the CLI (`internal/smallstep`), not in the aspect. The
aspect only ships the CLI and the DAG into the shell.

The registry entry is `ca-manager = ./aspects/ca-manager.nix;` in `modules/den/lib.nix`, next to
`ca = ./aspects/ca.nix;`.

## Verification steps

All commands exit 0:

| Command | Result |
|---|---|
| `nix build --no-eval-cache -L '.#checks.x86_64-linux.den-eval-certificates'` | 25 of 25 assertions pass |
| `nix build --no-eval-cache -L '.#checks.x86_64-linux.standalone-aspects'` | 3 of 3 assertions pass |
| `nix build --no-eval-cache -L '.#checks.x86_64-linux.den-eval-coverage'` | 1 of 1 assertions pass |
| `nix build --no-eval-cache -L '.#checks.x86_64-linux.den-smoke-devenv-linux'` | the `enterTest` runs `kdn-certs --help` |

`checks/den-mvp/assertions/certificates.nix` holds the `ca-manager` subjects: the single `devenv`
class, the `kdn-certs` package in the shell, the CA DAG option set through `includes`, the
`enterTest` command, and the library-route resolve.

`checks/den-mvp/devenv/default.nix` names `kdn.ca-manager` in its own `includes`, so the standalone
shell is the one subject that reaches the package and the `enterTest`.

## Follow-up notes

**The YubiKey prompt is the CLI's job.** The aspect ships the CLI; `kdn-certs apply` and
`kdn-certs ca sign` prompt for the touch inside `sops`, as design § 6 states.

**`den-eval-instantiate` is unverified on this host** (environmental `aarch64-darwin` pull). The
`ca-manager/devenv` pair is forced by the same code path; a Darwin host must confirm.
