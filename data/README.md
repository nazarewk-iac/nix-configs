---
type: Reference
description: Layout and sort rule for the personal data modules that keep private values out of the modules.
timestamp: 2026-09-11T00:00:00Z
authored_by: agent
---

# `data/`

`data/` holds the owner's personal values. Every module in `modules/universal/`, `modules/slots/`
and `modules/den/` declares an option with a neutral default. A file here assigns the owner's real
value to that option. So a module names no personal host, no personal path and no personal
network. An external adopter deletes `data/` and the tree still evaluates with the neutral
defaults.

Each `.nix` file here is a **module**, not a data value. A consumer imports it by path. Every
import sits behind `builtins.filter builtins.pathExists`, so an absent file is a no-op.

## Sort rule

Apply the five steps in order. The first match wins.

| # | Test | Directory |
|---|---|---|
| 1 | The file references `kdnConfig` in any way (argument, `kdnConfig.self`, `kdnConfig.util`, `kdnConfig.features`). | `universal-deps/` |
| 2 | No `kdnConfig`, and every consumer is under `modules/universal/**`. | `universal-safe/` |
| 3 | No `kdnConfig`, and every consumer sits in one system kind only. | `nixos/`, `darwin/` or `hm/` |
| 4 | Nothing above fits. | `data/` top level — ask the owner |
| 5 | Every consumer is a slot or a den aspect, through `mkSlots { imports = … }` or a den entity. | `slots/` |

Rule 1 beats rule 3. When both match, the row carries a `Kind:` note, so a later re-sort is
possible.

Rule 5 also beats rule 3 and rule 4, so read it first. A slot consumer is a stronger signal than
the system kind: a slot evaluates in its own universe, and the file must move with the slot.

`nixos/`, `darwin/` and `hm/` hold no file today. No current file matches rule 3.

A non-Nix payload file is not a data module. The three CA files go in `ca/` for that reason.

Each file keeps its base name. The directory carries the kind, so a name such as
`services-samba.nix` stays as it is.

## `universal-deps/` — reads `kdnConfig`

| File | What it holds | Read by | Shape |
|---|---|---|---|
| `desktop-sway-kanshi.nix` | The owner's monitors and their sway workspace arrangement. Kind: home-manager under a NixOS parent (rule 1 beats rule 3). | `modules/universal/default.nix` import list | function of `config`, `lib`, `kdnConfig`, `osConfig` |
| `development-nix.nix` | The absolute path of the owner's checkout of this repository. Kind: nixos and darwin host (rule 1 beats rule 3). | `modules/universal/default.nix` import list | function of `config`, `kdnConfig` |
| `stylix.nix` | The URL and hash of the owner's wallpaper. | `modules/universal/default.nix` import list | function of `lib`, `pkgs`, `kdnConfig` |

## `universal-safe/` — no `kdnConfig`

| File | What it holds | Read by | Shape |
|---|---|---|---|
| `hw-edid.nix` | Three EDID modelines, keyed by monitor name. | `modules/universal/default.nix` import list | attrset, was a function |
| `locale.nix` | The local time zone, the national keyboard layout and the extra locale list. | `modules/universal/default.nix` import list | attrset, was a function |
| `programs-photoprism.nix` | The path of the owner's photo source directory. | `modules/universal/default.nix` import list | function of `config` |
| `services-printing.nix` | One printer: name, location, device URI and driver. | `modules/universal/default.nix` import list | attrset, was a function |
| `services-samba.nix` | The Samba `hostsAllow` list: the home LAN plus loopback. | `modules/universal/default.nix` import list | attrset, was a function |

## `ca/` — CA payload files, not modules

| File | What it holds | Read by | Shape |
|---|---|---|---|
| `ca.pub` | The PEM public CA certificate. | `hosts/brys`, `hosts/oams` — `kdn.ca.kdn.certFile`, as a path string | payload file, not Nix |
| `ca.key.sops` | The SOPS-encrypted CA private key. | `hosts/brys`, `hosts/oams` — `kdn.ca.kdn.keySopsFile`, as a path string | payload file, not Nix |
| `ca.md` | The manual procedure to decrypt the key and to sign a leaf certificate. | a human reader only | Markdown |

`.gitignore` carries one negation per payload file. Add a new negation for a new payload file,
because line 5 ignores everything by default.

## `slots/` — read by a slot or a den aspect

| File | What it holds | Read by | Shape |
|---|---|---|---|
| `slots-ssh-access.nix` | The owner's SSH connectivity graph: host aliases, reach paths, uplink files and agent match patterns. | `hosts/anji`, `hosts/brys`, `hosts/oams` and the work host, through `mkSlots { imports = … }` | attrset, was a function |

Why the file sits here:

- Rule 5 matches. Every consumer reads the file through `mkSlots { imports = … }`, so the file
  belongs to the slot universe and not to a system kind.
- Rule 1 does not match. The evaluated body reads no `kdnConfig`. Only the header comment shows
  `kdnConfig.self` inside a usage example.
- Rule 2 does not match. No consumer is under `modules/universal/**`. The file feeds the
  `kdn.ssh-access` slot.
- Rule 3 does not match either. Two consumers are `nixos` hosts and two are `darwin` hosts, so the
  consumers span more than one system kind.

A host reads the file with a path literal behind `builtins.pathExists`, so a tree without the file
still evaluates. `modules/den/aspects/ssh-access.nix` reads the same option shape, so a future den
host puts its own data file here too.

## How to add a file

1. Pick the directory with the ladder above. Read the file's own body, not the module it feeds.
2. Give the file a header comment. Name the option it assigns and the fallback an adopter gets.
3. Read it from the module by a **relative path literal**, behind
   `builtins.filter builtins.pathExists`. Add one line to the list in
   `modules/universal/default.nix`, or to the host's own `imports`.
4. Run `git add data/<dir>/<file>`. An untracked file is invisible to the evaluation.
5. Write a plain attribute set when the body reads no module argument. Write a function only when
   the body needs `config`, `lib`, `pkgs`, `osConfig` or `kdnConfig`.

## Traps

Three measured facts. Each one costs time when you meet it for the first time.

- **An untracked file is invisible to a flake host evaluation.** `flake.nix` sets
  `nix-configs = self`, and the `.#` shorthand resolves through a `git+file://` fetcher. That
  fetcher reads git's tracked index. It shows an uncommitted edit to a tracked file, but it hides
  a brand-new untracked file. So a new data file needs `git add`. Confirm with
  `git ls-files -- data/`.
- **A `builtins.readFile` of an absent path aborts the whole evaluation.** `builtins.tryEval` does
  **not** catch that abort. So guard every path with `builtins.pathExists` first.
- **`lib.filesystem.listFilesRecursive` on an absent directory raises an error**, and `tryEval`
  does not catch that one either. So never scan `data/`. An explicit list of paths is the only
  safe form. Add one line per new file.
