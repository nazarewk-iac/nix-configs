---
type: Task
description: Replace hack/kdn-ca-sign.sh and the four manual zellij.{pub,key.sops} files with a kdn.certificates.certs.zellij-web declaration on oams, brys, etra and moss.
status: done
solution: done.md
parent: ../definition.md
authored_by: agent
timestamp: 2026-09-25T17:29:39+02:00
---

# 006 — zellij migration

Hub: [../definition.md](../definition.md). Depends on
[000-universal-augmentation](../000-universal-augmentation/definition.md),
[001-ca-dag](../001-ca-dag/definition.md), [002-cert-declarations](../002-cert-declarations/definition.md)
and [004-cert-cli](../004-cert-cli/definition.md).

The dependency on 000 is required. The four target hosts oams, brys, etra and moss are universal
(old-tree) hosts. They are not den hosts. Sub-task 000 augments a universal host with the
`kdn.certificates` aspect through
`denLib.imports { class = "nixos"; aspects = [ "certificates" ]; }`. Without that augmentation the
host declares no `kdn.certificates` option, and this migration cannot start.

Goal: the first real consumer of the certificate tree. Replace the manual zellij certificate flow
with a declaration. The `kdn.certificates` aspect then signs and consumes the certificate.

This sub-task is a plan. It writes no host edit and no aspect code.

## What goes away

Two manual pieces go away:

1. `hack/kdn-ca-sign.sh`. It decrypts `data/ca/ca.key.sops`, runs `openssl` by hand, writes the
   public cert and the SOPS key, and verifies against `data/ca/ca.pub`.
2. The four manual file pairs `hosts/<host>/certs/zellij.pub` and
   `hosts/<host>/certs/zellij.key.sops`, on oams, brys, etra and moss.

## What replaces them

One declaration on each of the four hosts:

```nix
kdn.certificates.certs.zellij-web = {
  ca = "kdn";
  type = "tls-server";
  commonName = "<host>.<zone>";
  sans = [ "<host>.<zone>" ];
  directory = "hosts/<host>/certs";
  certFile = "zellij.pub";
  keyFile = "zellij.key";
  keySource = "managed";
};
```

Each host names the aspect in its own `includes`. The four hosts are universal hosts, so they use
the sub-task 000 augmentation line instead of a den `includes` list:

```nix
imports = [ (denLib.imports { class = "nixos"; aspects = [ "certificates" ]; }) ];
```

`den.default` global injection is deliberately not used. No host receives the aspect without this
explicit line.

The `kdn` CA signs the leaf. Its `ssh` flag is off, because this leaf is TLS only. The `kdn-certs
apply` command generates the key, signs the cert, writes the public cert, and SOPS-encrypts the
private key.

The signing step prompts for the YubiKey touch. The CA private key is SOPS-sourced and encrypted to
YubiKey identities. The plan accounts for the prompt in the migration run.

## Consumption

The zellij web service reads the two exposed paths:

```nix
kdn.programs.zellij.web = {
  certFile = config.kdn.certificates.certs.zellij-web.certPath;
  keyFile = config.kdn.certificates.certs.zellij-web.keyPath;
  user = "kdn";
};
```

`certPath` is a store path, so it feeds `certFile`. `keyPath` is the decrypted runtime path, so it
feeds `keyFile` and not `keySopsFile`. The current host files set
`certFile = "${kdnConfig.self}/hosts/<host>/certs/zellij.pub"` and
`keySopsFile = "${kdnConfig.self}/hosts/<host>/certs/zellij.key.sops"` at
`hosts/oams/default.nix:347`, `hosts/brys/default.nix:484`, `hosts/etra/default.nix:448` and
`hosts/moss/default.nix:45`. Those four blocks change to the two `certPath`/`keyPath` reads.

The storage rule stays the same: the public cert is `<directory>/<certFile>` and it is committed
plain. The private key is `<directory>/<keyFile>.sops` and it is committed as raw/binary SOPS.

## Acceptance test

The plan defines four checks:

1. All four host toplevels evaluate:
   `nix eval .#nixosConfigurations.{oams,brys,etra,moss}.config.system.build.toplevel.drvPath`.
2. The service reads `certPath` and `keyPath`:
   `nix eval .#nixosConfigurations.oams.config.systemd.user.services.zellij-web.serviceConfig.ExecStart`.
   The output names the store cert path and the runtime key path.
3. The cert verifies against the CA:
   `openssl verify -CAfile data/ca/ca.pub hosts/oams/certs/zellij.pub`.
4. `kdn-certs apply` is idempotent. A second run changes no file.

## Out of scope

Do not change the zellij web service options. Do not move `data/ca/`. Do not remove
`data/ca/ca.key.sops`. Do not migrate the `llm` certificate on brys — that is a later consumer.
