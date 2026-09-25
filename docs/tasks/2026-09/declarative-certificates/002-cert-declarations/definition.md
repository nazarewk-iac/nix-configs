---
type: Task
description: Add the kdn.certificates aspect, the leaf cert-declaration drop-in that declares kdn.certificates.certs.<name> and exposes certPath and keyPath to consumers.
status: open
authored_by: agent
timestamp: 2026-09-25T17:29:39+02:00
parent: ../definition.md
---

# 002 — cert declarations

Parent task: [../definition.md](../definition.md). Design: [../design.md](../design.md).

## Context

`kdn.certificates` is the cert-declaration drop-in. It declares the leaf option set and wires
consumption: a store certificate path and a decrypted runtime key path. It signs nothing. The
`kdn-certs` CLI reads the declarations and generates the files.

The aspect covers four classes: `nixos`, `darwin`, `homeManager` and `devenv`. It declares no
`enable` option. Inclusion is the switch. An empty `kdn.certificates.certs` is the no-op, as
`checks/standalone.nix` requires.

The registry entry goes in `modules/den/lib.nix:36-242`, next to `ca = ./aspects/ca.nix;` at
`modules/den/lib.nix:38`.

## The option set

One leaf is `kdn.certificates.certs.<name>`:

| Option | Type | Default | Meaning |
|---|---|---|---|
| `ca` | a CA name from `kdn.ca-dag.cas` | required | The signing CA. |
| `type` | `"tls-server"`, `"tls-client"`, `"ssh-user"` or `"ssh-host"` | required | The certificate class. |
| `commonName` | string | required | The subject common name. |
| `sans` | list of strings | `[ ]` | The TLS subject alternative names. |
| `principals` | list of strings | `[ ]` | The SSH principals. |
| `directory` | string | `"hosts/<hostName>/certs"` | The repo-relative directory. |
| `certFile` | string | `"${name}.pub"` | The public certificate filename. |
| `keyFile` | string | `"${name}.key"` | The private key filename. The stored key is `<keyFile>.sops`. |
| `keySource` | `"external"` or `"managed"` | — | `external` means the key pre-exists. `managed` means the CLI generates the key. |
| `minGenerationDate` | `null` or ISO 8601 string | `null` | The oldest allowed generation date. |

The four classes split the two certificate families:

- `tls-server` and `tls-client` read `sans`.
- `ssh-user` and `ssh-host` read `principals`.

The `directory` default reads `kdn.hostName`. Import the shared declaration by path, as
`modules/den/common/host-name.nix` documents:

```nix
imports = [ ../common/host-name.nix ];
```

The module system dedupes an import by path, so many aspects load together and the option keeps one
declaration.

## Storage rule

The public certificate is `<directory>/<certFile>`. It is plain and committed. The private key is
`<directory>/<keyFile>.sops`. It is raw/binary SOPS and committed.

The aspect never decrypts the key. It declares the two paths. The `kdn-certs` CLI writes the files.
The existing zellij files follow the same rule: `hosts/oams/certs/zellij.pub` is plain and
`hosts/oams/certs/zellij.key.sops` is SOPS. See [006 — zellij migration](../006-zellij-migration/definition.md).

## The consumer surface

The aspect exposes two read-only paths for each leaf:

- `config.kdn.certificates.certs.<name>.certPath` — a store path to the public certificate.
- `config.kdn.certificates.certs.<name>.keyPath` — the decrypted runtime path of the private key.

A consumer reads the two paths. The zellij web service is the first consumer:

```nix
kdn.programs.zellij.web = {
  certFile = config.kdn.certificates.certs.zellij-web.certPath;
  keyFile = config.kdn.certificates.certs.zellij-web.keyPath;
  user = "kdn";
};
```

`certPath` feeds `certFile`. `keyPath` feeds `keyFile` and not `keySopsFile`, because the service
needs the decrypted key at run time. The current host files set
`certFile = "${kdnConfig.self}/hosts/<host>/certs/zellij.pub"` and
`keySopsFile = "${kdnConfig.self}/hosts/<host>/certs/zellij.key.sops"` at `hosts/oams/default.nix:347`,
`hosts/brys/default.nix:484`, `hosts/etra/default.nix:448` and `hosts/moss/default.nix:45`.

## Inclusion

Inclusion is explicit. Every den host, user, home and standalone devenv shell names `kdn.certificates`
in its own `includes`. A standalone shell may instead use
`denLib.imports { aspects = [ "certificates" ]; }`. The design does not use `den.default` global
injection, so no entity receives the option set without its own `includes` entry.

A universal (old-tree) host reaches the option set through sub-task
[000 — universal augmentation](../000-universal-augmentation/definition.md), not through a den
entity. That sub-task returns plain modules from `denLib.imports` and drops them into the host
`imports`.

## Missing-option tolerance

Every read uses `builtins.attrByPath [ "kdn" "certificates" ] { } cfg` semantics. A target with no
`kdn.certificates` option returns an empty set and raises no error. So the CLI walk never fails on a
target that lacks the options. The same rule covers `kdn.ca-dag`.

## Acceptance

- The `nixos`, `darwin`, `homeManager` and `devenv` classes each evaluate with a bare consumer and an
  empty `kdn.certificates.certs`.
- A declared leaf returns the exact option values from the table.
- `certPath` is a store path and `keyPath` is the decrypted runtime path, for a declared leaf.
- A target with no `kdn.certificates` option returns an empty set and no error.
- Every den host, user, home and standalone devenv shell names `kdn.certificates` in its own
  `includes`. No `den.default` global injection exists.
- `checks/standalone.nix` passes for the `certificates` aspect: no reachable `enable`, no
  `kdnConfig`, no `modules/universal` and no `modules/meta`.
- `den-eval-instantiate` forces every `certificates/<class>` pair.
- A new area file `checks/den-mvp/assertions/certificates.nix` holds the bare-consumer subjects, as
  `checks/den-mvp/assertions/default.nix:71-82` loads them.

## Out of scope

- The CA DAG option set. See [001 — CA DAG](../001-ca-dag/definition.md).
- The CLI and the generation. See [004 — cert CLI](../004-cert-cli/definition.md).
- The signer and the server lifecycle. See [003 — CA manager](../003-ca-manager/definition.md).
- SSH trust and the SSH drop-in. See [005 — SSH CA](../005-ssh-ca/definition.md).
