---
type: Solution
description: Register `anji` with `aarch64-linux`, move the builder identity to the system SSH config, and make the remote-build account allowed but not trusted.
task: definition.md
authored_by: agent
timestamp: 2026-10-14T00:03:02+02:00
---

# Solution

## Root cause analysis

The build hook (`lix/legacy/build-remote.cc`) picks one of two worker operations by client trust:

- A **trusted** client sends the derivation with `buildDerivation`. `lix/libstore/build/worker.cc`
  builds that through `makeBasicDerivationGoal`, which sets `useDerivation = false`.
  `lix/libstore/build/derivation-goal.cc` then skips the build hook
  (`if (!worker.hook.available || !useDerivation) co_return HookResult::Decline{}`). The builder
  builds locally and never forwards to its own builders.
- An **untrusted** client uses `buildPathsWithResults`, which keeps the hook, so the builder
  forwards the build.

So a trusted remote builder cannot chain. This is the Lix caveat in
[docs/lix-caveats.md](../../../lix-caveats.md).

Two more defects blocked the path before that:

- The `anji` entry listed only darwin systems, so a client never selected it for `aarch64-linux`.
- The `Match User kdn-nix-remote-build` identity lived in a Home Manager block. `IdentityFile`
  reads the sops secrets of the target module type, and that set is empty in the Home Manager
  context, so `use` stayed `false` and the block never appeared. The daemon, which runs the hook as
  root, read no identity.

## Solution

`modules/universal/profile/remote-builders/default.nix`:

- Add `aarch64-linux` to the `anji` entry `systems`. Drop the `anji-linux-builder` entry.
- Replace the Home Manager `programs.ssh.settings."Match User …"` block with a system
  `programs.ssh.extraConfig` block that holds `IdentityFile`, `IdentitiesOnly yes`, and
  `BatchMode yes`.
- Move the remote-build group from `nix.settings.trusted-users` to `nix.settings.allowed-users`.
  A trusted user is implicitly allowed, so the account must join `allowed-users` in the same
  change.

`docs/lix-caveats.md` records the behaviour, the evidence, and the workaround.

## Verification steps

`oams` -> `anji` -> `ssh-ng://rosetta-builder`, a fresh `aarch64-linux` derivation:

```
$ nix build --builders 'ssh-ng://kdn-nix-remote-build@anji.lan.etra.net.int.kdn.im. aarch64-linux - 4 1' \
    --max-jobs 0 --impure --expr \
    'with import <nixpkgs> { system = "aarch64-linux"; }; runCommand "probe" {} "echo x > $out"'
building '…-probe.drv' on 'ssh-ng://kdn-nix-remote-build@anji.lan.etra.net.int.kdn.im.'...
building '…-probe.drv' on 'ssh-ng://rosetta-builder'...
copying path '…-probe' from 'ssh-ng://kdn-nix-remote-build@anji.lan.etra.net.int.kdn.im.'...
```

Before the trust fix the same command failed with `a 'aarch64-linux' … but I am a 'aarch64-darwin'`.

`anji` runs the new generation. `allowed-users` lists `@kdn-nix-remote-build`; `trusted-users` does
not.

## Follow-up notes

- A trusted builder still cannot chain. If another builder host ever needs to chain, give its
  build account the same allowed-but-untrusted treatment.
- `nix-store --realise --store ssh-ng://<builder>` chains even when the builder is trusted, because
  it uses `BuildPaths`, not `BuildPathsWithResults`. That is a useful one-off diagnostic.
