---
type: Task
description: Narrow the 1Password IdentityAgent blanket from `Host *` to the github hosts, and decide whether git signing needs a per-host scope.
status: open
authored_by: agent
timestamp: 2026-09-09T12:40:00+02:00
---

# Scope the SSH agent and the git signing key

A fork-only Home Manager module writes an `IdentityAgent` blanket for `Host *`. The blanket sends
every SSH connection to the 1Password agent. A shared public option then claws individual hosts
back out of that blanket. Narrow the blanket instead, and re-check whether the shared option still
has a purpose.

## Measured mechanism

All facts below are verified on the Darwin workstation on 2026-09-09.

### The include chain hides the setup

`~/.ssh/config` line 1 is:

```
Include ~/.ssh/config.d/*.config ~/.ssh/config.local
```

Read the include files. A grep that covers `~/.ssh/config` alone misses the whole setup.

`~/.ssh/config` is a symlink into `/nix/store/<hash>-home-manager-files/.ssh/config`. Never edit it
by hand. Edit the Home Manager module.

### The blanket and the compensation

Three files exist in `~/.ssh/config.d/`. Measured directive counts:

| File | `IdentityAgent` directives | `Host *` blanket |
|---|---|---|
| `40-kdn-ssh-access.config` | 2 | 0 |
| `50-1password.config` | 1 | 1 |
| `kdn.config` | 0 | 0 |

`IdentityAgent` **overrides `SSH_AUTH_SOCK`**. So the blanket in `50-1password.config` makes the
1Password agent serve every host. It bypasses the Home Manager agent
(`org.nix-community.home.ssh-agent`), which holds the `ED25519-SK` key. Nix fetchers call `ssh`, so
they honour the blanket too.

`ssh` takes the **first** obtained value for a directive. The shell expands the glob in sorted
order, so `40-` is read before `50-`. That is the whole compensation mechanism: the `40-` file wins.
**The file numbering is load-bearing.**

The `40-` file comes from the public `kdn-ssh-access` module. It declares, at
`packages/kdn-ssh-access/module.nix:127`:

```nix
identityAgentPatterns = lib.mkOption {
  type = lib.types.listOf lib.types.str;
  default = [ ];
  description = "Extra Host patterns forced to $SSH_AUTH_SOCK (e.g. direct LAN FQDNs/ranges).";
};
```

Consumers: `packages/kdn-ssh-access/default.nix:76`, `modules/slots/ssh-access/default.nix:50`, and
`modules/slots/ssh-access/kdn-graph.nix:39`.

### Why this matters beyond one workstation

A **shared public option exists only to compensate for a personal module's over-broad write**. That
is the pattern gap 6 of [generalization-plan.md](../generalization/definition.md) describes: personal
defaults inside shared options. An external adopter inherits `identityAgentPatterns` and no blanket,
so for them the option has no purpose at all.

### Signing is a separate mechanism, and also unscoped

The same fork-only module forces the git signing setup with `lib.mkForce`:
`programs.git.signing.format = "ssh"`, `gpg.ssh.program = op-ssh-sign`, and the jj
`signing.behavior = "own"`. `~/.config/git/config` sets `gpgSign = true` globally, not per host.

A per-host signing scope needs `includeIf "hasconfig:remote.*.url:...github.com..."`. That is a
different mechanism from the `IdentityAgent` change. Treat it as a separate decision.

### Consequence for the YubiKey tap rule

Which agent answers depends on which `config.d` file matches first:

- A host the blanket matches — today every host, github included — reaches **1Password**. That asks
  for a desktop or a biometric approval. It is **not** a YubiKey tap.
- A host listed in `identityAgentPatterns` reaches `SSH_AUTH_SOCK` and the `ED25519-SK` key. That
  needs **a physical tap**.

So do not gate a github fetch on a tap. Keep the gate for the LAN and the homelab hosts.

## Work items

- [ ] Narrow the blanket in the fork-only module from `Host *` to `Host github.com gist.github.com`.
      This edit lands on the fork chain.
- [ ] Re-check `identityAgentPatterns` after the narrow. It probably shrinks to an empty list. If it
      does, decide whether the option stays as a general capability or goes away. This decision
      lands on the public chain, because the option is public.
- [ ] Decide whether git signing needs the `includeIf "hasconfig:remote.*.url:..."` scope, or
      whether a global `gpgSign = true` is acceptable. Record the decision either way.
- [ ] Re-verify the tap behaviour per host class after the change, and correct the tap rule if the
      answer moves.

## Exit criteria

- [ ] `~/.ssh/config.d/50-1password.config` holds no `Host *` blanket.
- [ ] A `ssh -G <a-homelab-host>` reports the `SSH_AUTH_SOCK` agent, not the 1Password socket.
- [ ] A `ssh -G github.com` reports the 1Password socket.
- [ ] The `identityAgentPatterns` decision is recorded, and gap 6 of the generalization plan cites
      this task as evidence.

## Out of scope

- The `40-`/`50-` file numbering. It works, and the narrow removes the need to rely on it.
- Any change to the `ED25519-SK` key itself, or to the Home Manager agent.
- The public `kdn-ssh-access` host graph. Another task owns the move of the personal graph into the
  personal folder.
