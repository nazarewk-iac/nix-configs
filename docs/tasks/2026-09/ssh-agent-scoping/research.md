---
type: Research
description: Measured mechanism of SSH authentication, SSH commit signing, and the switch between two signing keys on the Darwin workstation.
task: definition.md
authored_by: agent
timestamp: 2026-09-10T17:00:00+02:00
---

# How authentication, signing and the route switch work

This file promotes an earlier research run out of a git-ignored worklog. That is why the work was
hard to find. Every fact below is measured on the Darwin workstation on 2026-09-09 or 2026-09-10.
`<principal>` replaces each e-mail address.

## Two levers, fully independent

| Lever | Reads `ssh_config`? | Reads `$SSH_AUTH_SOCK`? | Steers |
|---|---|---|---|
| `ssh` | yes | yes, unless `IdentityAgent` overrides it | authentication |
| `ssh-keygen -Y sign` | **no** | yes, and `-f` also works | signing |
| `op-ssh-sign` | no | **no** | signing |
| `git` (`gpg.ssh.program`) | — | — | which signer runs |
| `jj` (`signing.backends.ssh.program`) | — | — | which signer runs |

`ssh-keygen` holds no `ssh_config` string in the binary. `-Y sign` accepts no config-file flag. So
`ssh_config` cannot change or repair signing. `op-ssh-sign` talks to the password manager
application over its own channel, so the agent socket cannot reach it either.

## Measured facts

1. `~/.ssh/config` line 1 is an `Include ~/.ssh/config.d/*.config ~/.ssh/config.local`. A grep of
   `~/.ssh/config` alone misses the whole setup.
2. `~/.ssh/config.d/50-1password.config` set `IdentityAgent` under a **`Host *`** blanket.
   `IdentityAgent` overrides `SSH_AUTH_SOCK`, and `ssh` keeps the **first** value it reads for a
   directive. So `SSH_AUTH_SOCK` cannot switch the key. Only a command-line
   `-o IdentityAgent=<path>` wins, or an earlier and narrower `Host` block.
3. The shell expands the include glob in sorted order, so `40-kdn-ssh-access.config` is read before
   `50-1password.config`. That order was the whole compensation mechanism: the `40-` file claws
   individual patterns back to `SSH_AUTH_SOCK`. **The file numbering was load-bearing.**
4. Measured `ssh -G` results before the narrow: `github.com` → the 1Password socket; `kdn-brys` →
   `SSH_AUTH_SOCK`; a bare `brys` → the 1Password socket, because no `40-` pattern matches a bare
   short name.
5. A plain OpenSSH agent runs already (`org.nix-community.home.ssh-agent`) and owns
   `SSH_AUTH_SOCK`. `ssh-add -l` against it reports **no identities**. The 1Password agent answers
   on its own socket and holds one key, `1Password GitHub Key (ED25519)`.
6. git config state: `gpg.format = ssh`, `commit.gpgSign = true`, `tag.gpgSign = true`,
   `gpg.ssh.program` = the 1Password `op-ssh-sign` binary.
7. `gpg.ssh.allowedSignersFile` was **empty**, and jj's `signing.backends.ssh.allowed-signers` was
   **unset**. So `jj log -T 'signature.status()'` reports `SIGNED bad` on real commits. **Nothing
   verified.** This is the one defect that a rebuild alone fixes.
8. jj `signing.behavior = "own"` compares the commit author e-mail against `user.email`. An
   alternate config that changes the e-mail makes jj sign nothing, in silence. `"force"` avoids it.
9. `signing.backends.ssh.program` takes one file name and **no arguments**. A wrapper script is the
   only way to pass a flag or an environment value.
10. **A failed signature stops every jj command, a read included.** Each command snapshots the
    working copy first, and the snapshot writes a commit that must be signed. `status`, `log` and
    `diff` all exit 255. Escape hatches: `jj status --ignore-working-copy`,
    `jj --config signing.backend=none <cmd>`, or `--config signing.behavior=drop`.
11. `signing.behavior = "keep"` still signs new work once anything in the chain carries a
    signature. Use `drop` to turn signing off.
12. Every relevant file in `~/.ssh/`, `~/.config/git/` and `~/.config/jj/` is a `/nix/store`
    symlink. Confirm with `ls -la` before you rely on it. Never edit one by hand.
13. A repo-local jj config lives at `~/.config/jj/repos/<hash>/config.toml`, outside the
    repository. It is never committed, and each jj workspace reaches the same file.

## Facts measured for the route switch, 2026-09-10

14. `JJ_CONFIG` takes a **list** of paths, separated by the platform path separator, and a later
    path wins (`cli/src/config.rs`, `resolve_user` calls `split_paths`). So an overlay file needs
    no copy of `user.name` or `user.email`.
15. jj 0.45.1 expands a leading `~` in `signing.key` and in `signing.backends.ssh.allowed-signers`
    (`lib/src/ssh_signing.rs`, `expand_home_path`). A **relative** `signing.key` is still read as
    inline key material, so an absolute path stays the safe choice.
16. `GIT_CONFIG_GLOBAL` replaces the whole global file. An `[include] path = <the real global
    file>` brings the credential helpers and the diff settings back. A **missing** include target
    is silently ignored — measured in a throwaway repository.
17. A plain `ssh-keygen` route verifies end to end. In a throwaway `/tmp` repository, with a
    throwaway key, `git log --show-signature` reported `Good "git" signature`, and
    `jj log -T 'signature.status()'` reported `good` for both the git-made and the jj-made commit.
18. The `gh` token on this workstation holds the scopes `gist`, `read:org`, `repo` and `workflow`.
    It holds **neither** `admin:public_key` **nor** `admin:ssh_signing_key`, so `gh api user/keys`
    and `gh api user/ssh_signing_keys` both answer HTTP 404. A key registration needs
    `gh auth refresh -h github.com -s admin:public_key,admin:ssh_signing_key` first. The token
    comes from the macOS keyring, not from 1Password.
19. `gh ssh-key add [<key-file>] --title <t> --type {authentication|signing}`. GitHub keeps the two
    types as two separate objects with two separate id spaces, at `user/keys` and
    `user/ssh_signing_keys`. So one public key needs **two** registrations.
20. macOS has no `shred` by default, but the Nix `coreutils` on PATH provides one. `/bin/rm -P`
    overwrites; the `coreutils` `rm` on PATH rejects `-P`. On APFS a copy-on-write snapshot can
    keep an old block, so no overwrite is a guarantee of erasure.

## Consequence for the tap rule

Which agent answers depends on which `config.d` file matches first:

- a host the 1Password pattern matches reaches 1Password, which asks for a desktop or a biometric
  approval. That is **not** a YubiKey tap.
- every other host reaches `SSH_AUTH_SOCK` and the `ED25519-SK` key. That needs **a physical tap**.

So do not gate a github fetch on a tap. Keep the gate for the LAN and the homelab hosts.
