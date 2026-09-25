---
type: Task
description: Rotate the unattended KDN root CA to a touch-required CA, with a migration window for the leaves.
status: open
parent: ../definition.md
authored_by: agent
timestamp: 2026-09-26T00:00:00+02:00
---

# 007 — CA rotation to a touch-required CA

Hub: [../definition.md](../definition.md). Follows
[006-zellij-migration](../006-zellij-migration/definition.md).

## Context

Decision D-B (2026-09-25) introduced a fresh managed root CA, `kdn.ca-dag.cas.kdn`. Its private key
`data/ca/kdn.key.sops` is encrypted to the two **unattended** YubiKey identities
`yk-oams-unattended` and `yk-brys-unattended` only — no touch and no PIN. That choice let
`kdn-certs ca init` run unattended, which the design needed to create the CA at all.

The unattended recipients are a deliberate, temporary weakening. A stolen unattended YubiKey can
decrypt the CA key with no user presence, so the CA key is not protected by a touch. The final
custody rule of decision D1 is YubiKey-touch confirmed for every real CA operation. This task
closes the gap between the D-B bootstrap and the D1 target.

## Goal

Rotate the `kdn` root CA to a key encrypted to the **touch-required** YubiKey identities, and
migrate the leaves that the old CA signed. The rotation must not break a running consumer: the
zellij web certificate on oams, brys, etra and moss stays valid through the change.

## What changes

1. **The CA key recipients.** `data/ca/kdn.key.sops` is re-encrypted to the touch-required
   identities. The exact recipient set is a security choice and belongs to the task owner. The
   `.sops.yaml` rule `data/ca/kdn\.key\.sops$` names them, above the generic `.*\.key\.sops` rule.
2. **A fresh CA key and root certificate, or the same key re-encrypted.** Two routes are open:
   - **Re-encrypt in place.** Keep the CA key and the root certificate, and change only the
     recipients of the SOPS file. The leaves stay valid, so no leaf re-sign is needed. The
     unattended identities are removed from the recipient set.
   - **Regenerate the CA.** Create a new key and a new self-signed root, switch the recipients to
     the touch-required set, and re-sign every leaf. The old root stays trusted until the last leaf
     is re-signed, so the migration window holds both roots.
3. **The migration window.** During the window, the trust store holds both the old and the new root
   certificate, and each consumer accepts a leaf signed by either. The window closes when every
   leaf is re-signed by the new CA.
4. **The leaves.** `kdn-certs apply` re-signs the four zellij web certificates (and any later leaf)
   under the new CA. `kdn-certs apply` needs the touch-required identity, so the user runs it at a
   YubiKey.

## Acceptance test

1. `data/ca/kdn.key.sops` decrypts with a touch and fails without one.
2. The unattended identities `yk-oams-unattended` and `yk-brys-unattended` are absent from the
   `data/ca/kdn\.key\.sops$` rule.
3. Every leaf verifies against the current root CA:
   `openssl verify -CAfile data/ca/kdn.crt hosts/<host>/certs/zellij.pub`.
4. `kdn-certs apply` is idempotent after the rotation.
5. The four host toplevels evaluate.

## Out of scope

Do not change the leaf option shape. Do not change the `ca-dag` option shape. Do not touch
`data/ca/ca.pub` or `data/ca/ca.key.sops` — the old "KDN LLM CA" is a separate CA. Do not migrate
the `llm` certificate on brys; that is a later consumer.
