---
type: Task
description: Rotate the unattended KDN root CA to a touch-required CA, with a migration window for the four zellij leaves.
status: open
parent: ../definition.md
authored_by: agent
timestamp: 2026-09-26T00:00:00+02:00
---

# 007 — CA rotation to a touch-required CA

Hub: [../definition.md](../definition.md). Follows
[006-zellij-migration](../006-zellij-migration/definition.md). Read this file alone: it is
self-contained.

## Context

Decision D-B (2026-09-25) introduced a fresh managed root CA, `kdn.ca-dag.cas.kdn`. It is declared
once in `data/ca/ca-dag.nix` and imported by the four hosts oams, brys, etra and moss:

```nix
kdn.ca-dag.cas.kdn = {
  type = "root";
  commonName = "KDN certificates root CA";
  directory = "data/ca";
  certFile = "kdn.crt";
  keyFile = "kdn.key";
  keySource = "managed";
  ssh = true;
};
```

`kdn-certs ca init` created the pair: the public certificate `data/ca/kdn.crt` and the
SOPS-encrypted private key `data/ca/kdn.key.sops`. `kdn-certs apply` then signed the four zellij web
leaves `hosts/{oams,brys,etra,moss}/certs/zellij.pub` with this CA. The leaves are committed.

The private key `data/ca/kdn.key.sops` is encrypted to the two **unattended** YubiKey identities
`yk-oams-unattended` and `yk-brys-unattended` only — no touch and no PIN. The `.sops.yaml` rule
`data/ca/kdn\.key\.sops$` names them. That choice let `kdn-certs ca init` run unattended, which the
design needed to create the CA at all.

The unattended recipients are a deliberate, temporary weakening. A stolen unattended YubiKey can
decrypt the CA key with no user presence, so the CA key is not protected by a touch. The final
custody rule of decision D1 is YubiKey-touch confirmed for every real CA operation. This task
closes the gap between the D-B bootstrap and the D1 target.

## Current state, in one table

| Item | Today |
|---|---|
| CA node | `kdn.ca-dag.cas.kdn` in `data/ca/ca-dag.nix` |
| Public certificate | `data/ca/kdn.crt` (committed) |
| Private key | `data/ca/kdn.key.sops` (committed, raw/binary SOPS) |
| Recipients | `yk-oams-unattended`, `yk-brys-unattended` — no touch, no PIN |
| Signing leaves | `hosts/{oams,brys,etra,moss}/certs/zellij.pub`, issuer `CN=KDN certificates root CA` |
| Trust | each leaf is consumed by its own host's zellij web service through `certPath`/`keyPath` |
| Old CA (untouched) | `data/ca/ca.pub` and `data/ca/ca.key.sops` — the separate "KDN LLM CA" |

## Target state

| Item | Target |
|---|---|
| Recipients | touch-required YubiKey identities only; the two `*-unattended` identities are removed |
| CA key use | a decrypt needs a physical touch |
| Leaves | still valid under the current root, or re-signed by the new root |
| Consumers | the four zellij web services keep working through the change |

## What changes

1. **The CA key recipients.** `data/ca/kdn.key.sops` is re-encrypted to the touch-required
   identities. The `.sops.yaml` rule `data/ca/kdn\.key\.sops$` names them, above the generic
   `.*\.key\.sops` rule. The exact recipient set is a security choice and belongs to the task owner.

2. **A fresh CA key and root certificate, or the same key re-encrypted.** Two routes are open:

   - **Route A — re-encrypt in place.** Keep the CA key and the root certificate `data/ca/kdn.crt`,
     and change only the recipients of the SOPS file. The four leaves stay valid, so no leaf
     re-sign is needed. The unattended identities are removed from the recipient set. This route is
     the smaller one and it does not need a leaf migration window.
   - **Route B — regenerate the CA.** Create a new key and a new self-signed root, switch the
     recipients to the touch-required set, and re-sign every leaf. The old root stays trusted until
     the last leaf is re-signed, so the migration window holds both roots.

3. **The migration window (Route B only).** During the window, the trust store holds both the old
   and the new root certificate, and each consumer accepts a leaf signed by either. The window
   closes when every leaf is re-signed by the new CA. Route A needs no window: the root does not
   change.

4. **The leaves.** `kdn-certs apply` re-signs the four zellij web certificates (and any later leaf)
   under the new CA. `kdn-certs apply` needs the touch-required identity, so the user runs it at a
   YubiKey.

## Exact commands

The commands below are the shape of the run. The recipient set is the task owner's choice; the
placeholder `<touch-recipient>` stands for one touch-required identity.

```bash
# 1. Re-encrypt the CA key to the touch-required recipients (Route A).
#    `--filename-override` selects the `data/ca/kdn\.key\.sops$` rule by the destination path.
sops decrypt --output-type binary data/ca/kdn.key.sops > /tmp/kdn.key
sops encrypt --output-type binary \
  --filename-override data/ca/kdn.key.sops \
  --output data/ca/kdn.key.sops \
  --age <touch-recipient> /tmp/kdn.key
rm -f /tmp/kdn.key

# 2. Confirm the touch requirement.
sops decrypt --output-type binary data/ca/kdn.key.sops > /dev/null   # must prompt for a touch

# 3. Confirm the leaves still verify against the root.
for h in oams brys etra moss; do
  openssl verify -CAfile data/ca/kdn.crt "hosts/$h/certs/zellij.pub"
done

# 4. Re-sign every leaf under the CA (idempotent when the root did not change).
kdn-certs apply --flake .

# 5. Confirm the second run changes nothing.
kdn-certs apply --flake .
```

Route B adds a root regeneration before step 1 and a leaf re-sign after it, with both roots in the
trust store until step 4 finishes.

## Acceptance test

1. `data/ca/kdn.key.sops` decrypts with a touch and fails without one.
2. The unattended identities `yk-oams-unattended` and `yk-brys-unattended` are absent from the
   `data/ca/kdn\.key\.sops$` rule.
3. Every leaf verifies against the current root CA:
   `openssl verify -CAfile data/ca/kdn.crt hosts/<host>/certs/zellij.pub`.
4. `kdn-certs apply` is idempotent after the rotation.
5. The four host toplevels evaluate:
   `NIX_CONFIG='netrc-file = /dev/null' nix eval --no-eval-cache --raw '.#nixosConfigurations.<host>.config.system.build.toplevel.drvPath'`.

## Out of scope

Do not change the leaf option shape. Do not change the `ca-dag` option shape. Do not touch
`data/ca/ca.pub` or `data/ca/ca.key.sops` — the old "KDN LLM CA" is a separate CA. Do not migrate
the `llm` certificate on brys; that is a later consumer. Do not change the SSH principals, the
certificate lifetimes or the trust scope.

## Follow-up notes

The SSH sign branch of `kdn-certs apply` is [008-apply-ssh-signing](../008-apply-ssh-signing/definition.md).
It does not block this task: the four zellij leaves are TLS leaves, and the TLS sign path is wired.
