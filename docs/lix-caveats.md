---
type: Reference
description: Lix behaviours that surprise an operator, with the observed evidence and the workaround.
timestamp: 2026-10-13T21:00:00+02:00
---

# Lix caveats

## A trusted remote builder does not forward a build to its own builders

**Symptom.** A client sends an `aarch64-linux` build to a remote builder. The
remote builder is an `aarch64-darwin` host. That host runs a QEMU
`aarch64-linux` builder VM, and its own `nix.buildMachines` lists that VM. The
build fails on the remote host with:

```
error: a 'aarch64-linux' with features {} is required to build '<drv>',
       but I am a 'aarch64-darwin' with features {...}
```

The same build succeeds in two other cases:

- The remote host runs the build itself.
- The client asks the remote host through
  `nix-store --realise --store ssh-ng://<host>`.

**Cause.** The build hook picks one of two worker operations. The choice
depends on the trust of the client.

- `lix/legacy/build-remote.cc` reads `sshStore->isTrustedClient()`. A trusted
  client, or a legacy `ssh://` store, sends the derivation with
  `buildDerivation` (worker op `BuildDerivation`). An untrusted client sends
  the closure, then `buildPathsWithResults` (op `BuildPathsWithResults`).
- `lix/libstore/build/worker.cc` builds a `BuildDerivation` request through
  `makeBasicDerivationGoal`. That goal holds `useDerivation = false`.
- `lix/libstore/build/derivation-goal.cc` skips the build hook when
  `useDerivation` is false:
  `if (!worker.hook.available || !useDerivation) co_return HookResult::Decline{};`

So a **trusted** client turns the build hook off on the remote host. The
remote host then builds locally. It cannot build the foreign system, so the
build fails. An **untrusted** client keeps the hook, so the remote host
forwards the build to its own builders.

A host must also sit in `allowed-users`, or the daemon refuses the connection.
A trusted user is implicitly allowed. So a host that leaves `trusted-users`
must join `allowed-users` in the same change.

**Workaround (this repository).** The remote-builder account joins
`allowed-users` and stays out of `trusted-users`. See
`modules/universal/profile/remote-builders/default.nix`. A builder host then
forwards each foreign build to its own builders.

**Evidence (2026-10-13, Lix 2.95.3 client, Lix 2.95.2 builder).**

| Command | Result |
|---|---|
| `nix build` from the client, builder trusted | fails: `but I am a 'aarch64-darwin'` |
| `nix-store --realise --store ssh-ng://<builder>` | forwards to the VM |
| `nix build` from the client, builder allowed but untrusted | forwards to the VM |

The third row is the fix.
