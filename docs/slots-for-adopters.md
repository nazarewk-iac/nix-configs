---
type: How-To
description: How an external adopter consumes this repository's modules/slots tree in their own repo.
timestamp: 2026-09-11T06:43:55+02:00
authored_by: agent
---

# Slots for an external adopter

This page is for an **external adopter** — anybody other than the author of this repository. It
tells you how to use the `modules/slots` tree in your own repository, which is called the **adopter
repo** below.

Read this page first. Then read [modules/slots/README.md](../modules/slots/README.md) for the
architecture and [.agents/rules/slots-standalone.md](../.agents/rules/slots-standalone.md) for the
rule that keeps a slot independent. This page does not repeat either of them.

A copy-ready starting point is in [templates/adopter/](../templates/adopter/README.md).

> **Draft state.** Every fact below is verified against the tree at the timestamp above. A line
> reference and a default value both drift fast, so check the frontmatter date against the
> revision you consume. One item is marked `TODO(verify)`, and you must not trust that item until
> somebody clears it.

> **Two routes exist. Read this before you pick one.**
>
> | Route | Real consumers in this repository | State |
> |---|---|---|
> | slots — this page | 5 host directories under `hosts/`, plus the root `devenv.nix` | the route the repository runs on |
> | den aspects — [docs/den-for-adopters.md](den-for-adopters.md) | none; every den entity is a test artifact under `checks/den-mvp/` | evaluated, never activated |
>
> So the slot route is proven in daily use, and the den route is proven only by evaluation. The
> den route is the newer surface, and it needs no overlay and no `mkSlots` call. The repository
> owner has not chosen between the two —
> [006-direction-decision](tasks/2026-09/generalization/006-direction-decision/definition.md)
> is open. Expect this page to change when that decision lands.
>
> **All 19 slots have a den aspect.** There are 21 aspects: one per slot, plus `homebrew` and
> `homebrew-nix-managed`, which have no slot. So you can reach every slot through either route.
> See
> [modules/den/README.md](../modules/den/README.md).

## What a slot is

A slot is one module at `modules/slots/**/default.nix`. It declares its own options under
`kdn.<name>` and it emits configuration into one or more **targets**. It is deliberately
self-contained: a slot uses only `lib`, `pkgs`, `config`, `options`, `inputs` and `moduleType`,
plus plain nixpkgs options. A slot never reads an option that `modules/universal` or `modules/meta`
declares. That rule is what makes a slot safe for you to adopt — those two trees hold the author's
personal data and they will be rewritten.

There are **19** slots today. Count them with `find modules/slots -name default.nix`: that returns
20 files, and `modules/slots/default.nix` is the recursive loader, not a slot.

| Slot | Slot | Slot |
|---|---|---|
| `ca` | `llm/proxy` | `nix` |
| `devenv` | `mcp` | `opencode` |
| `gh` | `mcp/basic-memory` | `rosetta-builder` |
| `jj` | `mcp/pretty-print` | `signing` |
| `jj/fork` | `mcp/snoop` | `ssh-access` |
| `llm` | | `ssh-agent` |
| `llm/client` | | `zellij` |

## The five targets

`lib/slots/schema.nix` declares exactly five targets. A slot writes into these, never into a flat
`config`.

| Target | Consumer | Note |
|---|---|---|
| `nixos` | NixOS system modules | |
| `darwin` | nix-darwin modules | |
| `home` | home-manager modules for every user | goes through `sharedModules` |
| `devenv` | devenv.sh modules | most slots target this one |
| `users` | per-user home-manager modules, keyed by user name | declared, and no slot assigns it today |

## The API: call `mkSlots`

The supported entry point is the flake output `inputs.nix-configs.mkSlots` (`flake.nix:309`). Do
not look for plain NixOS or nix-darwin modules. The flake exports the whole `modules/universal`
tree as `nixosModules.default` and `darwinModules.default` (`flake.nix:308,352`), it exports no
per-slot plain module, and it exports no `homeModules` at all.

`mkSlots` takes **one** attrset. It removes `pkgs` and treats everything that is left as a module,
so your slot settings and an `imports` list both go in the same attrset. It returns a `config`
attribute with one entry per target:

```nix
(inputs.nix-configs.mkSlots {
  inherit pkgs;
  kdn.<slot>.enable = true;
  # imports = [ ./more-slot-settings.nix ];   # optional
}).config.devenv    # or .config.nixos / .darwin / .home / .users
```

You do **not** pass your own `inputs`. `mkSlots` builds `specialArgs.inputs` from this
repository's own inputs, with `nix-configs` bound to the repository itself, so a slot always
resolves the files it reads. `.config.users` is an attrset of user name to module, ready for
`home-manager.users.<name>`.

`lib.kdn.mkSlots` is the lower-level function underneath (`lib/slots/default.nix`). It takes
`{ slotModules, specialArgs }` and returns `renderTarget` and `renderUsers`. Use it only when you
need to control `specialArgs`. `checks/jj-experiments/devenv.nix` is the in-repo precedent for that
lower-level route.

### Worked example: a devenv shell

`devenv.yaml`:

```yaml
inputs:
  nixpkgs:
    # Point this at YOUR nixpkgs. Do NOT write `follows: nix-configs/nixpkgs`.
    # This repo's nixpkgs input is the author's own fork.
    url: github:NixOS/nixpkgs/nixos-unstable
  nix-configs:
    url: github:nazarewk-iac/nix-configs
```

`devenv.nix`:

```nix
{ inputs, pkgs, ... }:
{
  imports = [
    (inputs.nix-configs.mkSlots {
      inherit pkgs;
      kdn.zellij.enable = true;          # one small slot as a worked example
      # `kdn.mcp.snoop.enable` and `kdn.mcp.pretty-print.enable` both default to false, so this
      # example needs no line for either. Set one to true only when you want that child.
    }).config.devenv
  ];

  overlays = [ inputs.nix-configs.overlays.packages ];
}
```

This repository's own `devenv.nix` uses exactly this shape, so the example is not hypothetical.
The one line it adds that you must not copy is `kdn.isSourceRepo = true` — see below.

## Hard requirement: add the packages overlay

**You must add `overlays = [ inputs.nix-configs.overlays.packages ]`.** Nothing in the slot tree
tells you this, and a slot fails to evaluate without it. devenv's `overlays` option needs devenv
1.4.2 or newer.

Seven slots need it, because they reference `pkgs.kdn.*`:

`jj`, `llm`, `llm/proxy`, `mcp/basic-memory`, `mcp/snoop`, `ssh-access`, `zellij`.

Use `overlays.packages`, not `overlays.default`. `overlays.default` also composes NUR, microvm,
angrr, nix-darwin, devenv and oh-my-pi, and you almost certainly do not want those.

## What a slot writes into your repo

This is the part that surprises an adopter. Several slots do not only configure a shell — they
write files into the adopter repo, and some of those files instruct an AI agent how to behave.

**Five slots copy content out of this repository through `${inputs.nix-configs}/.agents/…`:**
`jj`, `jj/fork`, `nix`, `zellij` and `mcp/basic-memory`. The files land as symlinks into
`/nix/store/`, under `.claude/` in your repo.

State plainly what that means:

- **`kdn.jj` installs the author's jj-only mandate as an agent rule.** It writes
  `.claude/rules/jujutsu-vcs.md` and a `jujutsu-vcs` skill, and it registers a `jj-expert` agent.
  That rule forbids nearly all raw `git` use. Adopt it only when you want that policy.
- **`kdn.nix`** writes `.claude/rules/okf-format.md` plus the `flake-update` and `flake-patches`
  skills. The flake-update skill describes **this** repository's update procedure.
- **`kdn.zellij`** writes `.claude/skills/zellij/SKILL.md`.
- **`kdn.mcp.basic-memory`** writes `.claude/rules/basic-memory.md`.
- **`kdn.jj.fork`** writes the fork-specific update rule and skill, and it installs git hooks.

A single option controls all of it: `kdn.isSourceRepo` (`modules/slots/default.nix:15`). It is
`false` by default, and `false` means "install the agent files". Set it `true` only inside this
repository itself. So an adopter gets these files unless the adopter disables the slot.

### Every slot stays off until you enable it

Each slot declares `enable` with `lib.mkEnableOption`, so each one defaults to `false`. That
includes `kdn.mcp.snoop` and `kdn.mcp.pretty-print`, which an earlier version of this page named
as exceptions. They are not exceptions any more. You write no line to keep a slot off.

### Personal defaults: three that are already neutral

An earlier version of this page named three personal defaults. All three are gone. Measured on
2026-09-11:

| Option | Default today | Note |
|---|---|---|
| `kdn.jj.upstream.remote` | `"origin"` | `modules/slots/jj/default.nix:56`; the git default |
| `kdn.jj.alwaysBlockedMessagePatterns` | `[ ]` | `modules/slots/jj/default.nix:44`; a pattern belongs to one repository |
| `kdn.opencode.settings` | `{ }` | `modules/slots/opencode/default.nix:141`; the slot names no provider |

This repository sets its own values in its own `devenv.nix`, not in the slot. So you inherit
nothing personal from these three. Other slots may still carry a personal default;
[007-depersonalize-slots](tasks/2026-09/generalization/007-depersonalize-slots/definition.md)
tracks the rest.

## The jj pre-push guard: what it does and does not protect

`kdn.jj.fork` installs a `pre-push` hook that refuses to push content matching a private pattern
list to any remote other than your private one. The hook is `modules/slots/jj/pre-push.sh`, and
[checks/jj-experiments/test_prepush.md](../checks/jj-experiments/test_prepush.md) states the
per-remote matrix that 15 tests prove.

Understand its limits before you rely on it:

- **`jj git push` fires no git hook.** Measured. The hook runs only on a real `git push`. Treat it
  as one net, not the gate.
- **`prek` hands a `pre-push` hook no stdin**, so the hook cannot always tell what you push. It
  fails closed for a public remote and passes for the private one. Set
  `KDN_JJ_PRE_PUSH_RANGE='<range>'` to name the range by hand.
- The pattern list comes from a git-ignored local file. When that file is absent the hook fails
  **loudly** instead of passing in silence. `KDN_JJ_PRE_PUSH_ALLOW_EMPTY=1` is the explicit escape
  hatch.
- **A delete-only push to a public remote fails closed.** That is safe, and it is a false positive.

## Verify your setup

Run both checks from your own repo, not from this one.

```bash
# 1. One option evaluates. This is the fast check — it builds no derivation.
devenv eval 'enterShell'

# 2. The whole shell evaluates and its packages build.
devenv build shell

# 3. It works with NO ssh agent. An adopter must never need a key from this repo.
SSH_AUTH_SOCK= \
GIT_SSH_COMMAND='ssh -o BatchMode=yes -o IdentitiesOnly=yes -o IdentityFile=/dev/null' \
  devenv build shell
```

Check 1 alone is not enough. `devenv eval` confirms evaluation only; it does not prove a package
compiles.

`TODO(verify)` — check 2 against a real adopter repo outside this tree. The reasoning says it must
pass, because a lock node that nothing references is never fetched, but that is not yet measured
from an adopter's position.

## What this page does not cover

- The `modules/universal` and `modules/meta` trees. They hold personal data and they are not for
  you.
- Turning a slot into a plain nix-darwin or NixOS module. The den route already does that for
  every aspect, `rosetta-builder` included: one flake input and one `imports` entry, with no
  `mkSlots` call. See [den-for-adopters.md](den-for-adopters.md). Checkpoint 002 measured it and
  added no second module.
- Consuming the tree without flakes.
