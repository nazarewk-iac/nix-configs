---
type: How-To
description: How an external adopter imports this repository's den aspects as plain NixOS, nix-darwin, Home Manager or devenv modules.
timestamp: 2026-09-11T00:41:03+02:00
authored_by: agent
---

# den aspects for an external adopter

This page is for an **external adopter** — anybody except the author of this repository. It tells
you how to use the `modules/den/aspects/` tree in your own repository, the **adopter repo**.

Read [modules/den/README.md](../modules/den/README.md) for the architecture. This page does not
repeat it. [docs/slots-for-adopters.md](slots-for-adopters.md) describes the older
`modules/slots/` route, which stays in place.

> **Every command below ran on `aarch64-darwin`, against revision
> `ab1c207522dcf720965f7459614258eab408f1df`.** Six scratch projects outside this repository held
> the commands. Each one used a local `git+file:` flakeref with `?rev=<that revision>`. The
> examples print the public `github:` form instead. That is the one difference.

## What an aspect is

An aspect is one file at `modules/den/aspects/<name>.nix`. It declares its own options under
`kdn.<something>`, and it emits configuration into one or more **classes**. A class is one
evaluation domain: `nixos`, `darwin`, `homeManager` or `devenv`.

One rule makes an aspect a drop-in:

> **Inclusion is the switch. An aspect declares no `enable` option.**

You import the module, and the aspect is on. Nothing else turns it on. Most aspects start from a
neutral default, so an import alone changes little until you supply your own values. `homebrew`
starts with three empty lists. `ssh-access` starts with an empty host graph. `signing` starts with
no key. Three aspects do not start neutral — see caveat 10.

Two more rules follow from the first, and they are what make the import free of machinery:

- **An aspect takes no entity argument.** No aspect reads a den host or a den user. So no aspect
  needs den on your side.
- **A target module takes `config`, `lib` and `pkgs` only.** Every NixOS, nix-darwin, Home Manager
  and devenv evaluation already gives you these three arguments.

So you pass **no `specialArgs`, no `kdnConfig` and no overlay**. This is the measured difference
from the `modules/slots/` route, which needs one `overlays` line.

## The two entry points

| Handle | Shape | Use |
|---|---|---|
| `denModules.<aspect>` | an already-resolved plain module | one aspect, in its one common class |
| `denLib.imports { class; aspects; }` | a **list** of plain modules | any aspect, in any class it emits |

`denModules.<aspect>` drops straight into a `modules` list.

`denLib.imports` returns a **list**, so it needs an `imports` wrapper:

```nix
{ imports = nix-configs.denLib.imports { class = "devenv"; aspects = [ "gh" ]; }; }
```

A bare list in a `modules` list fails. Measured:

```
error: Module imports can't be nested lists. Perhaps you meant to remove one level of lists?
```

An unknown aspect name fails at once, when you build the list, and it prints every known name:

```
error: den: no aspect named `hg`.
Known aspects: ca, devenv-cli, gh, homebrew, jj, jj-fork, llm, llm-client, llm-proxy, mcp, …
```

## Minimal examples that work

Each example below evaluated with exit code 0. The table at the end of this section names the
command per example.

### nix-darwin

```nix
{
  inputs.nix-configs.url = "github:nazarewk-iac/nix-configs";
  inputs.nixpkgs.follows = "nix-configs/nixpkgs";
  inputs.nix-darwin.follows = "nix-configs/nix-darwin";

  outputs =
    { nix-darwin, nix-configs, ... }:
    {
      darwinConfigurations.example = nix-darwin.lib.darwinSystem {
        system = "aarch64-darwin";
        modules = [
          nix-configs.denModules.rosetta-builder
          nix-configs.denModules.homebrew
          {
            system.stateVersion = 6;
            system.primaryUser = "adopter";
            users.users.adopter.home = "/Users/adopter";
            nixpkgs.hostPlatform = "aarch64-darwin";

            kdn.homebrew.taps = [ "example-org/example-tap" ];
            kdn.homebrew.casks = [ "example-cask" ];
            # nix-darwin's own default is "none". This aspect keeps the author's "zap", which
            # deletes a package the generated Brewfile does not name. Set it back yourself.
            kdn.homebrew.onActivation.cleanup = "none";
          }
        ];
      };
    };
}
```

### NixOS

```nix
{
  inputs.nix-configs.url = "github:nazarewk-iac/nix-configs";
  inputs.nixpkgs.follows = "nix-configs/nixpkgs";

  outputs =
    { nixpkgs, nix-configs, ... }:
    {
      nixosConfigurations.example = nixpkgs.lib.nixosSystem {
        modules = [
          nix-configs.denModules.ca
          nix-configs.denModules.llm

          # `llm-proxy` emits two classes, so it has no `denModules` entry.
          { imports = nix-configs.denLib.imports { class = "nixos"; aspects = [ "llm-proxy" ]; }; }

          (
            { pkgs, ... }:
            {
              nixpkgs.hostPlatform = "x86_64-linux";
              system.stateVersion = "25.05";
              boot.loader.grub.devices = [ "/dev/sda" ];
              fileSystems."/".device = "/dev/sda1";
              fileSystems."/".fsType = "ext4";

              kdn.ca.example.enable = true;
              kdn.ca.example.certFile = pkgs.writeText "example-ca.pub" "-- your CA certificate --\n";
            }
          )
        ];
      };
    };
}
```

### Home Manager (standalone)

```nix
{
  inputs.nix-configs.url = "github:nazarewk-iac/nix-configs";
  inputs.nixpkgs.follows = "nix-configs/nixpkgs";
  inputs.home-manager.follows = "nix-configs/home-manager";

  outputs =
    { nixpkgs, home-manager, nix-configs, ... }:
    {
      homeConfigurations.adopter = home-manager.lib.homeManagerConfiguration {
        pkgs = nixpkgs.legacyPackages.aarch64-darwin;
        modules = [
          nix-configs.denModules.signing
          nix-configs.denModules.ssh-agent

          # `ssh-access` emits two classes, so it has no `denModules` entry.
          { imports = nix-configs.denLib.imports { class = "homeManager"; aspects = [ "ssh-access" ]; }; }

          {
            home.username = "adopter";
            home.homeDirectory = "/Users/adopter";
            home.stateVersion = "25.05";

            # `signing` gates its WHOLE body on this option. Without it you get nothing.
            programs.git.enable = true;
            programs.git.settings.user.name = "A Adopter";
            programs.git.settings.user.email = "adopter@example.invalid";

            kdn.signing.allowedSigners = [
              {
                principals = [ "adopter@example.invalid" ];
                key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIExampleExampleExampleExampleExampleExam";
              }
            ];

            kdn.ssh-access.defaults.user = "adopter";
            kdn.ssh-access.uplinks.home.ipv4 = "192.0.2.10";
            kdn.ssh-access.hosts.gate.reachedFrom = [
              { from = "internet"; uplink = "home"; port = 2222; }
              { from = "lan"; address = "198.51.100.7"; priority = 10; }
            ];
          }
        ];
      };
    };
}
```

A den host reaches a `homeManager` aspect through a **user**, never through the host. So put
`signing`, `ssh-agent` and `ssh-access` in your `home-manager.users.<name>` module, not beside
your NixOS or nix-darwin modules.

### devenv, through the devenv CLI

`devenv.yaml`:

```yaml
inputs:
  nix-configs:
    url: github:nazarewk-iac/nix-configs
  nixpkgs:
    follows: nix-configs/nixpkgs
  # Mandatory for `nix` and `jj-fork`. The devenv CLI does NOT supply it. See caveat 2.
  git-hooks:
    url: github:cachix/git-hooks.nix
    inputs:
      nixpkgs:
        follows: nixpkgs
  # Optional. Only the `mcp` family needs it. See caveat 3.
  mcp-servers-nix:
    url: github:natsukium/mcp-servers-nix
```

`devenv.nix`:

```nix
{ inputs, lib, ... }:
{
  imports = inputs.nix-configs.denLib.imports {
    class = "devenv";
    aspects = [
      "gh"
      "devenv-cli"
      "nix"
      "jj"
    ];
  };

  kdn.mcp.serversNix = inputs.mcp-servers-nix;

  # Two baseline MCP servers do not build today. See caveat 9.
  kdn.mcp.programs.filesystem.enable = lib.mkForce false;
  kdn.mcp.programs.sequential-thinking.enable = lib.mkForce false;
}
```

You add **no** `overlays` line. That is the difference from the slot route.

### devenv, with no devenv CLI

devenv is a plain `lib.evalModules` target. Use this shape when your flake builds the shell
itself.

```nix
{
  inputs.nix-configs.url = "github:nazarewk-iac/nix-configs";
  inputs.nixpkgs.follows = "nix-configs/nixpkgs";
  inputs.devenv.follows = "nix-configs/devenv";

  outputs =
    { nixpkgs, devenv, nix-configs, ... }:
    let
      system = "aarch64-darwin";
    in
    {
      packages.${system}.shell =
        (nixpkgs.lib.evalModules {
          class = "devenv";

          # devenv reads an integration input straight out of `specialArgs.inputs`.
          # The `nix` aspect registers git hooks, so `git-hooks` must be present. See caveat 2.
          specialArgs.inputs = {
            inherit nixpkgs;
            git-hooks = devenv.inputs.git-hooks;
          };

          modules = [
            (devenv.outPath + "/src/modules/top-level.nix")
            {
              _module.args.pkgs = nixpkgs.legacyPackages.${system};
              name = "adopter-shell";
              devenv.root = "/path/to/your/repo";   # mandatory, and never a store path
              devenv.tmpdir = "/tmp";
            }
            # Silence the CLI-versus-modules mismatch, and drop devenv's task prelude.
            (
              { config, lib, ... }:
              {
                devenv.cli.version = lib.mkDefault config.devenv.latestVersion;
              }
            )
            {
              imports = nix-configs.denLib.imports {
                class = "devenv";
                aspects = [ "gh" "nix" ];
              };
            }
          ];
        }).config.shell;
    };
}
```

### The verified commands

| Example | Command | Exit |
|---|---|---|
| nix-darwin | `nix eval --no-eval-cache --raw '.#darwinConfigurations.example.config.system.build.toplevel.drvPath'` | 0 |
| NixOS | `nix eval --no-eval-cache --raw '.#nixosConfigurations.example.config.system.build.toplevel.drvPath'` | 0 |
| Home Manager | `nix eval --no-eval-cache --raw '.#homeConfigurations.adopter.activationPackage.drvPath'` | 0 |
| devenv, CLI | `devenv build shell` | 0 |
| devenv, no CLI | `nix eval --no-eval-cache --raw '.#packages.aarch64-darwin.shell.drvPath'` | 0 |

Four more evaluations cover **every** aspect in **every** class it emits — 25 aspect-class pairs
across 20 aspects. All four exit 0:

| Class | Aspects in one evaluation |
|---|---|
| `devenv` | `devenv-cli`, `gh`, `jj`, `jj-fork`, `llm-client`, `llm-proxy`, `mcp`, `mcp-basic-memory`, `mcp-pretty-print`, `mcp-snoop`, `nix`, `opencode`, `ssh-access`, `zellij` |
| `nixos` | `ca`, `devenv-cli`, `llm`, `llm-proxy` |
| `darwin` | `devenv-cli`, `homebrew`, `rosetta-builder` |
| `homeManager` | `devenv-cli`, `signing`, `ssh-access`, `ssh-agent` |

## The 20 aspects

| Aspect | Classes | `denModules` | What it gives you |
|---|---|---|---|
| `ca` | `nixos` | yes | Trusts your own certificate authorities as system CAs. |
| `devenv-cli` | `nixos`, `darwin`, `homeManager`, `devenv` | **no** | Puts the `devenv` CLI on PATH. The one four-class aspect. |
| `gh` | `devenv` | yes | The GitHub CLI, plus a read-only Bash allowlist for Claude Code. |
| `homebrew` | `darwin` | yes | Turns nix-darwin's `homebrew` module on. Three empty lists, three `onActivation` values. |
| `jj` | `devenv` | yes | The `jj` binary, a repo config, an agent rule, a `jj-mcp` backend. Includes `mcp`. |
| `jj-fork` | `devenv` | yes | The fork-remote half: 2 remotes, 20 revset aliases, 5 aliases, 2 git hooks. Includes `jj`. |
| `llm` | `nixos` | yes | Serves local GGUF models from one `llama-server` router, behind one Caddy vhost. |
| `llm-client` | `devenv` | yes | One opencode provider per remote llama-server endpoint. Includes `opencode`. |
| `llm-proxy` | `nixos`, `devenv` | **no** | Runs `opencode-compat-proxy` instances that translate raw tool calls to OpenAI JSON. |
| `mcp` | `devenv` | yes | One `mcp-gateway` process, and one Claude Code registration for it. |
| `mcp-basic-memory` | `devenv` | yes | One gateway backend per knowledge base. Includes `mcp-pretty-print`. |
| `mcp-pretty-print` | `devenv` | yes | Replaces the Claude Code approval dialog with a Tk preview. Includes `mcp`. |
| `mcp-snoop` | `devenv` | yes | Puts `mcpsnoop` in front of the gateway as a JSON-RPC traffic proxy. Includes `mcp`. |
| `nix` | `devenv` | yes | Two Nix language servers, the formatter, a pre-commit hook, 2 MCP backends. Includes `mcp`. |
| `opencode` | `devenv` | yes | A project `opencode.jsonc`, plus a credential wrapper named `opencode` on PATH. |
| `rosetta-builder` | `darwin` | yes | An on-demand `aarch64-linux` plus `x86_64-linux` Linux builder VM for Apple Silicon. |
| `signing` | `homeManager` | yes | An `allowed_signers` file, an alternate git/jj signing pair, `kdn-signing` on PATH. |
| `ssh-access` | `homeManager`, `devenv` | **no** | Topology-aware ssh. Each `kdn-<name>` alias picks the cheapest route at connect time. |
| `ssh-agent` | `homeManager` | yes | OpenSSH `ssh-agent` in place of the macOS built-in agent, so a FIDO2 security key works. |
| `zellij` | `devenv` | yes | zellij plus two helper packages, two Claude Code hooks, one agent skill. |

Verify the list yourself:

```bash
nix eval --no-eval-cache --json '<flakeref>#denLib.aspectModules' --apply builtins.attrNames   # 20
nix eval --no-eval-cache --json '<flakeref>#denModules'          --apply builtins.attrNames   # 17
```

### The option prefix does not always match the aspect name

Six aspects declare no option at all: `devenv-cli`, `gh`, `mcp-snoop`, `rosetta-builder`,
`ssh-agent` and `zellij`. For the rest, the prefix is this:

| Aspect | Option prefix |
|---|---|
| `ca` | `kdn.ca.<instance>` |
| `homebrew` | `kdn.homebrew` |
| `jj` | `kdn.jj` |
| `jj-fork` | `kdn.jj.fork`, plus `kdn.jj.alwaysBlockedMessagePatterns` |
| `llm` | `kdn.llm.local` |
| `llm-client` | `kdn.llm.client` |
| `llm-proxy` | `kdn.llm.proxy` |
| `mcp` | `kdn.mcp` |
| `mcp-basic-memory` | `kdn.mcp.basic-memory` |
| `mcp-pretty-print` | `kdn.mcp.pretty-print` |
| `nix` | `kdn.nix` |
| `opencode` | `kdn.opencode` |
| `signing` | `kdn.signing` |
| `ssh-access` | `kdn.ssh-access` |

No rule maps an aspect name to its option prefix. Read the aspect file when you are not sure.

## How to override a value, and how to turn one off

An aspect writes into your own configuration. So the module system's priority rules apply, with no
special case.

A lower number wins. Four priorities matter:

| Definition | Priority | Wins against |
|---|---|---|
| `lib.mkForce x` | 50 | everything below |
| a plain assignment | 100 | every default |
| `lib.mkDefault x` | 1000 | an option's own declared default |
| an option's own `default = x` | 1500 | nothing |

Two definitions at the **same** priority do not resolve. A mergeable type concatenates them, and a
scalar type stops the evaluation.

Two consequences:

1. **Where an aspect writes `lib.mkDefault`, your plain value wins.** Measured: `gh` sets
   `claude.code.enable = lib.mkDefault true`. A plain `claude.code.enable = false` in `devenv.nix`
   then resolves to `false`.
2. **Where an aspect writes a plain value, your plain value collides.** Measured: `mcp` sets
   `kdn.mcp.programs.filesystem.enable = true` at plain priority. A plain `false` on your side then
   stops the evaluation:

   ```
   error: The option `kdn.mcp.programs.filesystem.enable' has conflicting definition values:
   - In `devenv@kdn/mcp': true
   - In `/…/devenv.nix': false
   ```

`lib.mkForce` clears that error. **Treat every `lib.mkForce` as a defect report, not as the
interface.** An aspect that makes you write `mkForce` states an opinion. It must declare a
`lib.mkDefault` instead. Open an issue for it. Do not accept `mkForce` as the documented route.
That route hides a real conflict behind a higher priority. It also breaks when two aspects force
the same option.

**To turn an aspect off, do not set an option. Remove the import.** Inclusion is the whole switch.

## Caveats

Ten items. Each one is measured.

### 1. Three aspects have no `denModules` entry

`denModules.<aspect>` names exactly one class per aspect, so it cannot carry a multi-class aspect.

| Aspect | Classes | Reach it with |
|---|---|---|
| `devenv-cli` | 4 | `denLib.imports { class = "<one of the four>"; aspects = [ "devenv-cli" ]; }` |
| `llm-proxy` | 2 | `denLib.imports { class = "nixos"; … }` or `class = "devenv"` |
| `ssh-access` | 2 | `denLib.imports { class = "homeManager"; … }` or `class = "devenv"` |

`denLib.aspectModules` holds 20 names. `denModules` holds 17. Verified against
`modules/den/flake-module.nix`, which states the reason in a comment.

### 2. devenv needs an explicit `git-hooks` input

- **Symptom:** `error: Failed assertions: - To use 'git-hooks', run the following command: $ devenv
  inputs add git-hooks github:cachix/git-hooks.nix --follows nixpkgs`
- **Cause:** devenv reads `inputs.git-hooks` out of `specialArgs.inputs`, and it falls back to a
  stub that accepts no real hook. The `nix` and `jj-fork` aspects register real hooks. `jj-fork`
  includes `jj`, so a shell that takes `jj-fork` needs it too.
- **Fix, devenv CLI:** add the `git-hooks` input to `devenv.yaml`, as the example above shows.
- **Fix, hand-rolled:** pass `specialArgs.inputs.git-hooks = devenv.inputs.git-hooks;`.

Measured with devenv 2.3.1: the CLI does **not** supply the input by itself. Both routes need it.

### 3. `kdn.mcp.serversNix` defaults to `null`

- **Symptom:** the evaluation prints `warning: kdn.mcp.serversNix is null, so every
  kdn.mcp.programs declaration stays inert and only kdn.mcp.extraBackends reaches the gateway. Set
  kdn.mcp.serversNix to your own mcp-servers-nix source to turn the translation on.`
  The gateway starts, and it serves no `programs.*` backend.
- **Cause:** `mcp-servers-nix` is a `devenv.yaml` input of this repository, so no den evaluation
  reaches it. The aspect takes the source as a plain option instead.
- **Fix:** add your own `mcp-servers-nix` input, and set `kdn.mcp.serversNix = inputs.mcp-servers-nix;`.

The warning is not an error. The `mcp` family evaluates and builds with `serversNix = null` — `null`
builds no `programs.*` backend at all, so caveat 9 cannot bite.

### 4. `signing` is a silent no-op with no `programs.git.enable`

- **Symptom:** you import `denModules.signing`, you set `kdn.signing.allowedSigners`, and nothing
  changes. No `kdn-signing` binary, no `allowed_signers` file, no error and no warning.
- **Cause:** the aspect wraps its whole `config` in `lib.mkIf config.programs.git.enable`. The
  guard exists to skip a user with no git, for example root.
- **Fix:** set `programs.git.enable = true;` for that user.
- **Measured:** with the guard closed, `home.packages` held `man-db`,
  `home-configuration-reference-manpage` and `hm-session-vars.sh` — no `kdn-signing`. With
  `programs.git.enable = true`, the same configuration produced both `kdn-signing` and the
  `allowed_signers` store path.

### 5. `lib.mkForce` is no longer needed for `modules/universal`

An earlier state of this repository needed `lib.mkForce` on 14 options under
`modules/universal/profile/user/kdn/`. The cause: 13 modules forwarded a value into Home Manager
outside their own `lib.mkIf cfg.enable` guard. Commit `85cc3df9` moved every forward inside the
guard, and it converted all 14 assignments to `lib.mkDefault true`.

**That limit is gone.** `modules/universal/profile/user/kdn/` holds exactly one `lib.mkForce`
today, and it is unrelated (a systemd unit `Requires` list). This caveat exists only so you do not
copy the old advice from an older note.

One detail: commit `85cc3df9` landed **after** the revision the examples pin. So this paragraph
describes the current tree, not the pin. Pick a revision at or after `85cc3df9`.

`modules/universal/` is not for you in any case. It holds the author's personal data, and it will
be rewritten.

### 6. Cost: 103 lock nodes, and a large first fetch

See the [Cost](#cost) section below.

### 7. You need no ssh key

The lock holds exactly one `ssh://` input, and it is a public Homebrew tap on github.com. No aspect
reads it, and Nix never fetches a lock node that nothing references.

Measured — the nix-darwin example exits 0 with an empty agent:

```bash
SSH_AUTH_SOCK= \
GIT_SSH_COMMAND='ssh -o BatchMode=yes -o IdentitiesOnly=yes -o IdentityFile=/dev/null' \
  nix eval --no-eval-cache --raw '.#darwinConfigurations.example.config.system.build.toplevel.drvPath'
```

### 8. One harmless warning prints on every command

```
warning: input 'nix-configs/nixos-crostini' has an override for a non-existent input 'nixos-generators'
```

- **Cause:** this repository's `flake.nix` sets a `follows` for an input that
  `nixos-crostini` no longer declares.
- **Effect:** none. Ignore it.
- **Fix:** none on your side. It is this repository's own defect to clear.

### 9. Two baseline MCP servers do not build today

- **Symptom:** `devenv build shell` fails with an npm error inside
  `mcp-server-filesystem-2026.7.10.drv`: `error TS2591: Cannot find name 'process'`.
- **Cause:** the `mcp` aspect turns on four baseline `programs.*` servers — `filesystem`,
  `sequential-thinking`, `time` and `fetch`. Two of them fail to build from `mcp-servers-nix` on
  `aarch64-darwin`, at both the unpinned tip and the revision this repository pins.
- **Fix:** `kdn.mcp.programs.filesystem.enable = lib.mkForce false;` and the same for
  `sequential-thinking`. `lib.mkForce` is needed here because the aspect sets both at plain
  priority — this is the caveat in "How to override" made real.
- The evaluation always succeeds. Only the build fails.

### 10. Three aspects act on import

These three aspects change the machine at the first activation:

- `homebrew` turns nix-darwin's `homebrew` module on
  (`modules/den/aspects/homebrew.nix:122`), and `kdn.homebrew.onActivation.cleanup` defaults to
  `"zap"` (`modules/den/aspects/homebrew.nix:104-106`). `"zap"` deletes a hand-installed cask.
  **Fix:** set `kdn.homebrew.onActivation.cleanup = "none";` first.
- `llm` sets `services.llama-cpp.enable = true` with no guard
  (`modules/den/aspects/llm.nix:875`), so a router starts with no model.
  **Fix:** set `services.llama-cpp.enable = lib.mkForce false;`, or remove the import.
- `rosetta-builder` sets `nix-rosetta-builder.enable = true`
  (`modules/den/aspects/rosetta-builder.nix:29`), which builds a Linux VM.
  **Fix:** remove the import.

### A tool defect, not a repository defect

A Lix 2.95 eval-cache entry makes this fail:

```
$ nix eval --json '<flakeref>#denModules' --apply builtins.attrNames
error: 'packages.aarch64-darwin' is not an attribute set
```

`--no-eval-cache` fixes it. Reproduced with Lix 2.95.2 on `aarch64-darwin`. Pass
`--no-eval-cache` to every `nix eval` you run against a den output.

## Cost

Measured from the nix-darwin example, which is the smallest of the four.

| Item | Value | Measured with |
|---|---|---|
| lock nodes, without the root node | 103 | `jq` over the adopter `flake.lock` |
| by type | 97 `github`, 4 `git`, 1 `gitlab`, 1 `tarball` — the `github:` form gives 98 and 3 | same |
| `ssh://` inputs | 1, a public tap on github.com, and no aspect reads it | same |
| nixpkgs source tree | 334 MB | `du -sm` |
| every direct input, deduplicated | 1314 MB across 52 paths | `du -sm` over `nix flake archive --json` |
| full lock tree | about 3.0 GB across 92 paths | `nix flake archive` |
| first fetch of one evaluation | about 342 MB | **not repeatable here** — see below |

**Read those last three rows. They are not the same number.**

- **One evaluation** fetches only the nodes it reads. A cold-store run of the nix-darwin example
  came to about 342 MB, and nixpkgs is 334 MB of that. This document could not repeat that
  measurement, because the store was already warm. Treat 342 MB as an order of magnitude, not an
  exact figure.
- **Every direct input** is 1314 MB. An evaluation does not need all of them. The four largest are
  nixpkgs (334 MB), a second stable nixpkgs (294 MB), and two large program sources (182 MB and
  166 MB).
- **`nix flake archive`** is 3.0 GB, because several inputs pin their own nixpkgs copy. You do not
  need `nix flake archive`. Do not run it to "warm the cache".

Reduce the cost with a `follows` line, exactly as every example above does:

```nix
inputs.nixpkgs.follows = "nix-configs/nixpkgs";
```

## What is untested

- **A fully independent `nixpkgs`.** Every scratch flake used
  `inputs.nixpkgs.follows = "nix-configs/nixpkgs"`. An adopter who pins their own nixpkgs is
  plausible and untested. Two versions of nixpkgs then coexist. An aspect that reads a package
  from a relative `pkgs.callPackage` path gets **your** nixpkgs, not this repository's. Expect to
  find breakage there, and report it.
- **Any activation.** Every command was `nix eval` or `devenv build shell`. No
  `darwin-rebuild switch`, no `nixos-rebuild switch`, no `home-manager switch`.
- **Any build of a NixOS, nix-darwin or Home Manager closure.** Every check read a `drvPath`. Only
  `devenv build shell` built a derivation.
- **`x86_64-linux` and `aarch64-linux`.** Every measurement above ran on `aarch64-darwin`. The
  NixOS example evaluated `x86_64-linux` from a Darwin host, and it built nothing.
- **A real ssh connection.** `ssh-access` emits its drop-in and its binary. No test opened a
  session.
- **A second repository that exports the `kdn` den namespace.** den merges two sources by
  namespace name plus aspect name, so a name clash merges rather than shadows. See
  [modules/den/README.md](../modules/den/README.md) § "The two den namespaces".

## Where to look next

| Question | File |
|---|---|
| How does an aspect resolve into a plain module? | [modules/den/lib.nix](../modules/den/lib.nix) |
| Which class does `denModules.<aspect>` name, and why? | [modules/den/flake-module.nix](../modules/den/flake-module.nix) |
| What does one aspect really do? | `modules/den/aspects/<name>.nix` — each file opens with a full header |
| What is the older route? | [docs/slots-for-adopters.md](slots-for-adopters.md) |
