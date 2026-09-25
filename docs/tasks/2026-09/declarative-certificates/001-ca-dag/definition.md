---
type: Task
description: Add the kdn.ca-dag aspect, a data-only declaration of the CA graph in kdn.ca-dag.cas.<name>, with no generation and no system trust.
status: done
solution: done.md
authored_by: agent
timestamp: 2026-09-25T17:29:39+02:00
parent: ../definition.md
---

# 001 — CA DAG

Parent task: [../definition.md](../definition.md). Design: [../design.md](../design.md).

## Context

`kdn.ca-dag` is one of four aspects in the declarative-certificates design. It declares the CA graph
as data. It generates nothing and it trusts nothing. The `kdn-certs` CLI reads the graph and walks it
in topological order.

The aspect covers four classes: `nixos`, `darwin`, `homeManager` and `devenv`. It declares no
`enable` option. Inclusion is the switch. An empty `kdn.ca-dag.cas` is the no-op, as
`checks/standalone.nix` requires.

The registry entry goes in `modules/den/lib.nix:36-242`, next to `ca = ./aspects/ca.nix;` at
`modules/den/lib.nix:38`.

## Inclusion

Inclusion is explicit. Every den host, user, home and standalone devenv shell names `kdn.ca-dag` in
its own `includes`. A standalone shell may instead use
`denLib.imports { aspects = [ "ca-dag" ]; }`. The design does not use `den.default` global injection.

A universal (old-tree) host reaches the aspect through sub-task
[000 — universal augmentation](../000-universal-augmentation/definition.md). That sub-task returns
plain modules from `denLib.imports` and drops them into the host `imports`.

## The option set

One CA node is `kdn.ca-dag.cas.<name>`:

| Option | Type | Default | Meaning |
|---|---|---|---|
| `type` | `"root"` or `"intermediate"` | required | The node class in the DAG. |
| `parent` | `null` or a CA name | `null` | The parent CA. A root names no parent. |
| `commonName` | string | required | The subject common name of the CA. |
| `directory` | string | `"data/ca"` | The repo-relative directory of the CA files. |
| `certFile` | string | `"${name}.crt"` | The public certificate filename. |
| `keyFile` | string | `"${name}.key"` | The private key filename. The stored key is `<keyFile>.sops`. |
| `keySource` | `"external"` or `"managed"` | — | `external` means the key pre-exists, for example a YubiKey-backed key. `managed` means the CLI generates the key. |
| `provisioner` | `null` or string | `null` | The smallstep provisioner name. |
| `ssh` | bool | `false` | The CA also signs SSH certificates. |
| `minGenerationDate` | `null` or ISO 8601 string | `null` | The oldest allowed generation date. |

`minGenerationDate` accepts arbitrary precision: `YYYY`, `YYYY-MM`, `YYYY-MM-DD`,
`YYYY-MM-DDThh:mm`, `YYYY-MM-DDThh:mm:ss`, and any of these with a trailing `Z`. A missing component
takes its lowest value. The parser and the comparison belong to the CLI — see
[004 — cert CLI](../004-cert-cli/definition.md).

## The DAG

The `parent` field builds one directed acyclic graph. The CLI sorts it topologically: roots first,
then each intermediate, then the leaves. A `parent` that names no CA is a hard error. A cycle in
`parent` is a hard error. The sort belongs to the CLI. This aspect only declares the data.

## Where the data lives

The CA files live in `data/`. The default `directory` is `data/ca`. The existing tree already holds
`data/ca/ca.pub` and `data/ca/ca.key.sops`, and `hack/kdn-ca-sign.sh:69` verifies a leaf against
`data/ca/ca.pub`. So the declaration points at the same files that exist today.

The public certificate is plain and committed. The private key is raw/binary SOPS and committed. The
aspect never decrypts the key and never reads the file content. It declares paths only.

## Key custody

The CA private key is SOPS-sourced, exactly like `data/ca/ca.key.sops` today. The recipient set is a
`.sops.yaml` concern, not a code concern. The current recipients are YubiKey identities, so a real CA
sign operation needs a YubiKey touch. The CLI prompts for the touch when it signs with such a CA. See
[003 — CA manager](../003-ca-manager/definition.md).

More decryption candidates may be added later for automation. The design does not add them now. A
test CA may use an unattended key, encrypted to a test identity, so the test suite signs with no
YubiKey. The test CA lives outside `data/`, for example under `checks/` or a temporary directory.

## Why it is separate from `kdn.ca`

`kdn.ca` trusts a CA as a system CA. It has the `nixos` class only. It mounts `/etc/kdn/ca/<name>.pub`
and adds each file to `security.pki.certificateFiles` at `modules/den/aspects/ca.nix:100-105`. It
never generates a key and never signs a certificate.

`kdn.ca-dag` declares the graph. It emits no configuration, holds no system trust and starts no
process. The two aspects therefore have different classes, different jobs and different option trees.

Do not redeclare `options.kdn.ca` in the same class tree. `kdn.ca` declares it inside its own `nixos`
target at `modules/den/aspects/ca.nix:89`. The new tree uses the name `kdn.ca-dag`, so the two trees
cannot clash.

## Why the data layer stays inert

A host that consumes a certificate needs the DAG data, not the signer. So the data layer stays inert.
The separation gives three results:

- An empty `kdn.ca-dag.cas` is a true no-op.
- A consumer that reads the DAG pays no package build.
- `kdn.ca-dag` stays in four classes, while `kdn.ca-manager` stays devenv-only.

## Acceptance

- The `nixos`, `darwin`, `homeManager` and `devenv` classes each evaluate with a bare consumer and an
  empty `kdn.ca-dag.cas`.
- A declared root and a declared intermediate return the exact option values from the table.
- Every den host, user, home and standalone devenv shell names `kdn.ca-dag` in its own `includes`.
  No `den.default` global injection exists.
- `checks/standalone.nix` passes for the `ca-dag` aspect: no reachable `enable`, no `kdnConfig`, no
  `modules/universal` and no `modules/meta`.
- `den-eval-instantiate` forces every `ca-dag/<class>` pair.
- A new area file `checks/den-mvp/assertions/certificates.nix` holds the bare-consumer subjects, as
  `checks/den-mvp/assertions/default.nix:71-82` loads them.

## Out of scope

- The leaf option set. See [002 — cert declarations](../002-cert-declarations/definition.md).
- The CLI and its DAG sort. See [004 — cert CLI](../004-cert-cli/definition.md).
- The signer and the server lifecycle. See [003 — CA manager](../003-ca-manager/definition.md).
- SSH trust. See [005 — SSH CA](../005-ssh-ca/definition.md).
