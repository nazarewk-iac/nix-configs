---
type: Design
description: Design and parked state of the signing slot, the narrowed 1Password IdentityAgent block, and the plain-key route switch.
task: definition.md
authored_by: agent
timestamp: 2026-09-10T17:30:00+02:00
---

# Design: a verifiable signing setup with two routes

Measured mechanism: [research.md](research.md). Task: [definition.md](definition.md).
`<principal>` replaces each e-mail address.

## Goals

1. Make a signature **verifiable**. Today nothing verifies, because no `allowed_signers` file
   exists (research fact 7).
2. Give a **second signing route** that needs no password manager, and let one shell command switch
   between the two.
3. Keep the reusable part free of every personal value, so an external adopter can use it.

## Where the public module lives, and why

`modules/slots/signing/` — a slot, target `home`.

- The workstation host already calls `mkSlots` and already wires `slots.config.home` into
  `home-manager.sharedModules`. So the module reaches the real machine with **one enable line**.
- A slot is the current sharing surface, and the slots rule keeps it standalone. It reads no
  `modules/universal` option, so the planned rewrite of that tree cannot break it.
- `modules/den/` is out of scope: den reaches no live host yet.

## What the slot owns

| Part | Mechanism |
|---|---|
| `allowed_signers` | one generated store file, wired into **both** `gpg.ssh.allowedSignersFile` and jj `signing.backends.ssh.allowed-signers` |
| alternate git config | a store file that starts with `include.path = <the real global file>`, then overrides `user.signingKey`, `gpg.ssh.program` and `allowedSignersFile` |
| alternate jj config | a store TOML file with `signing.behavior = "force"`, `backend = "ssh"`, a plain key and plain `ssh-keygen` |
| `kdn-signing` | a script on PATH that **prints** the shell lines a route needs |

Options, all data-free:

- `kdn.signing.enable`
- `kdn.signing.allowedSigners` — a list of `{ principals; key; namespaces }`
- `kdn.signing.plain.keyFile` — default `~/.ssh/id_ed25519_kdn_plain`; the module never creates it

### Why the script prints lines

A child process cannot change the environment of its parent. So the caller runs the lines:
`eval "$(kdn-signing plain)"` in bash or zsh, `kdn-signing plain fish | source` in fish. The shell
comes from an argument or from `$SHELL`; every shell other than fish gets the `export` syntax.
Every printed line is a comment or an assignment, so an `eval` of any route is safe.

Routes: `plain`, `default` (`1p` is an accepted alias) and `status`.

`GIT_SSH_COMMAND` carries `-o IdentityAgent=$SSH_AUTH_SOCK`, unexpanded, so the caller's shell
expands it. A command-line `-o` beats every `ssh_config` file. That is the only way past an
`IdentityAgent` directive in a blanket block (research fact 2).

`JJ_CONFIG` gets **two** paths, the real user config and the overlay, because jj reads a list and a
later path wins (research fact 14). So the overlay repeats no personal value.

## The narrow of the 1Password block

`Host *` becomes `Host github.com gist.github.com ssh.github.com`, from a new `git.auth.hosts`
option of the fork-only 1Password module.

**If the list is too narrow**, an SSH connection to a host that needs the 1Password key fails with
`Permission denied (publickey)`. Recovery, with no rebuild, for one command:

```
ssh -o 'IdentityAgent=~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock' <host>
```

The permanent fix adds the host to that option. The narrow also removes the need for the `40-`/`50-`
file order and for the public `identityAgentPatterns` option (research facts 3 and 4).

## The shim key lifecycle — designed, NOT implemented

A git-ignored shim at `.cache/agent-notes/signing/` is to give the same switch before the rebuild.
The design below is recorded; **no file exists yet**.

- `up` — generate a fresh `ed25519` key with no passphrase, mode `600`, **inside the shim
  directory**; never reuse a key, never touch `~/.ssh/`. Register the same public key twice with
  `gh ssh-key add <file> --title 'kdn-signing-shim <host> <YYYY-MM-DD>' --type authentication` and
  again with `--type signing`. Write the `allowed_signers` file and the two alternate configs, then
  print the export lines. `up` is idempotent: a live key stops it.
- `down` — deregister both GitHub objects, then shred the key files, then remove the directory.
  **The fingerprint guard is mandatory:** compute `ssh-keygen -lf <public key>` and delete only an
  object whose SHA256 fingerprint equals it. A title match with no fingerprint match aborts with an
  error. That guard is what stops the shim from deleting the 1Password key or a YubiKey key. When
  the local key is already gone, `down` cannot compute a fingerprint, so it must refuse and name
  the title for a manual removal.
- `status` — three facts only: the local key exists, GitHub holds the authentication key, GitHub
  holds the signing key.
- `--dry-run` prints each `gh` command and runs none.
- **Shred limit, stated plainly:** macOS ships no `shred`, and the Nix `coreutils` `rm` on PATH
  rejects `-P`. `/bin/rm -P` overwrites, and `coreutils` `shred` is on PATH. On APFS a
  copy-on-write snapshot can keep an old block, so no overwrite proves an erasure.
- **`gh` dependency:** the token holds neither `admin:public_key` nor `admin:ssh_signing_key`
  (research fact 18), so `up` must first ask the user for
  `gh auth refresh -h github.com -s admin:public_key,admin:ssh_signing_key`. The token comes from
  the macOS keyring, so `gh` needs no password manager.

## Parked state, 2026-09-10

### Done so far

- `modules/slots/signing/default.nix` and `modules/slots/signing/kdn-signing.sh` — complete,
  formatted, and built.
- The fork-only 1Password module — the narrow plus the new `git.auth.hosts` option.
- The fork host configuration — `kdn.signing.enable` and one `allowedSigners` entry for the
  password-manager key. The plain key entry is a comment, because the key does not exist yet.

The last two paths stay out of this file on purpose. They belong to the fork chain, and this file
goes to the public chain.
- `research.md` — the promoted research.

### Remaining

- The shim at `.cache/agent-notes/signing/`. Nothing is written.
- A full `nix build` of the host system closure. Only the evaluation and the single new package are
  proven.
- The user must create the plain key, register it twice on GitHub, then add the second
  `allowedSigners` entry.
- Work item 2 of the task: decide the future of `identityAgentPatterns` after the narrow.

### Next directions

- Implement the shim `up`/`down`/`status` with `--dry-run`, then test the dry run only.
- After the rebuild, verify with `jj log -T 'signature.status()'` in this repository. Expect `good`
  in place of `SIGNED bad`.
- Re-measure `ssh -G github.com` and `ssh -G kdn-brys` after the rebuild, for the exit criteria.
