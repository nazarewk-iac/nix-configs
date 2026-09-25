---
type: Task
description: Add the kdn.ca-manager aspect, which puts the kdn-certs CLI and the CA DAG into a devenv shell and owns the smallstep server lifecycle.
status: open
authored_by: agent
timestamp: 2026-09-25T17:29:39+02:00
parent: ../definition.md
---

# 003 — CA manager

Parent task: [../definition.md](../definition.md). Design: [../design.md](../design.md).

## Context

`kdn.ca-manager` is one of four aspects in the declarative-certificates design. It has the `devenv`
class only. It puts the `kdn-certs` CLI and the CA DAG into a devenv shell. It also owns the
smallstep server lifecycle. The design spec calls it the manager and the signer.

The CLI itself is sub-task [004 — cert CLI](../004-cert-cli/definition.md). This sub-task covers
only the aspect and the process lifecycle.

## What the aspect emits

The aspect includes `kdn.ca-dag`, so the shell carries the CA DAG option set. It adds the
`kdn-certs` package to `config.packages`. It adds no service, no system trust and no file.

The package comes in by a relative path literal, as `./ssh-access.nix` does:

```nix
(pkgs.callPackage ../../../packages/kdn-certs { })
```

A relative path literal needs no overlay and no `pkgs.kdn.*` entry. It also keeps the evaluation
on one file.

The aspect declares no `enable` option. An empty CA DAG is the no-op, so inclusion alone changes
nothing. `checks/standalone.nix` enforces this rule.

## Why it is separate from `kdn.ca`

`kdn.ca` trusts a CA as a system CA. It has the `nixos` class. It mounts `/etc/kdn/ca/<name>.pub`
and adds each file to `security.pki.certificateFiles`. It never generates a key and never signs a
certificate.

`kdn.ca-manager` runs in a devenv shell. It holds no system trust. It owns the sign lifecycle. The
two aspects therefore have different classes, different jobs and different option trees.

Do not redeclare `options.kdn.ca` in the same class tree. The two trees must not clash.

## Why it is separate from `kdn.ca-dag`

`kdn.ca-dag` declares the option set only. It emits no configuration and it starts no process. It
is available in four classes: `nixos`, `darwin`, `homeManager` and `devenv`.

A host that consumes certificates needs the DAG data, not the CLI. So the data layer stays inert.
The separation gives three results:

- An empty `kdn.ca-dag.cas` is a true no-op, as `checks/standalone.nix` requires.
- A consumer that reads the DAG pays no package build.
- `kdn.ca-manager` stays devenv-only, while `kdn.ca-dag` stays in four classes.

## The smallstep server lifecycle

The CLI shells out to `step` and `step-ca`. `step-ca` runs only while one sign operation needs it.
The lifecycle has five steps:

1. Start `step-ca` as a transient process. Use a `systemd-run --user` unit, or a subprocess with a
   temporary `ca.json`.
2. Decrypt the CA private key. When the key is encrypted to YubiKey identities, prompt for the
   YubiKey touch and wait for it.
3. Sign the requested leaf or intermediate.
4. Terminate the process.
5. Clean the temporary `ca.json` and the PID file.

`step certificate create --ca … --ca-key …` and `step ca certificate --offline` both work with no
network. So the lifecycle needs no listening port and no long-lived daemon.

## Zombie discovery

A crash can leave a `step-ca` process or a stale PID file behind. `kdn-certs doctor` finds both.
The command scans the process table for a `step-ca` process and scans the CA directory for a stale
PID file. It reports each hit and removes it with `--force`.

`kdn-certs apply` runs the same scan on startup, before it signs anything. So a leftover process
cannot hold the CA port or the CA lock.

## Inclusion

Inclusion is explicit. Each standalone devenv shell that needs the manager names `kdn.ca-manager` in
its own `includes`, or uses `denLib.imports { aspects = [ "ca-manager" ]; }`. The design does not use
`den.default` global injection. The sites are:

- `checks/den-mvp/devenv/default.nix` — the standalone shell list.
- A host aspect list, where a host needs the CLI in its own shell.

A universal (old-tree) host reaches the CLI through sub-task
[000 — universal augmentation](../000-universal-augmentation/definition.md), not through a den
entity.

## Key custody and the YubiKey touch

The CA private key is SOPS-sourced, exactly like `data/ca/ca.key.sops` today. The current recipients
are YubiKey identities. So a real CA sign operation needs a YubiKey touch, and the CLI prompts for
the touch when it signs with such a CA. The prompt belongs to the sign step of the lifecycle above.

The recipient set is a `.sops.yaml` concern, not a code concern. More decryption candidates may be
added later for automation. The design does not add them now.

A test CA may use an unattended key, encrypted to a test identity, so the test suite signs with no
YubiKey. The test CA lives outside `data/`, for example under `checks/` or a temporary directory.

## Acceptance

- `nix eval --json '.#denDevenvShells.devenv-darwin.config.packages'` lists the `kdn-certs` package.
- `nix eval --json '.#denDevenvShells.devenv-darwin.config.kdn.ca-dag.cas'` returns the declared
  CA DAG.
- Each standalone devenv shell that needs the manager names `kdn.ca-manager` in its own `includes`.
  No `den.default` global injection exists.
- A sign with a YubiKey-backed CA prompts for the touch and waits for it.
- The test CA signs with an unattended key and no YubiKey.
- `checks/standalone.nix` passes for the `ca-manager` aspect: no reachable `enable`, no `kdnConfig`,
  no `modules/universal` and no `modules/meta`.
- `den-eval-instantiate` forces the `ca-manager/devenv` pair.
- The aspect's `enterTest` runs `kdn-certs --help` and asserts the exit code.

## Out of scope

- The CLI commands and their flags. See [004](../004-cert-cli/definition.md).
- The CA DAG option shape. See [001 — CA DAG](../001-ca-dag/definition.md).
- The leaf option shape. See [002 — cert declarations](../002-cert-declarations/definition.md).
- SSH trust. See [005 — SSH CA](../005-ssh-ca/definition.md).
