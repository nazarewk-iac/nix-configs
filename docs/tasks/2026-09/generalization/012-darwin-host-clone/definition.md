---
type: Task
description: A reference map that sizes a den reimplementation of the darwin workstation, plus three NixOS follow-on hosts and the parity method.
status: not-scheduled
authored_by: agent
timestamp: 2026-09-10T18:02:03Z
---

# 012 — clone the darwin workstation as a den host

Hub: [../definition.md](../definition.md). den design: [../../../../modules/den/README.md](../../../../modules/den/README.md).

**This document maps the work and sizes it. It is not a schedule.** Nobody runs it next. The
aspect port keeps the order table in [004-den-spike/definition.md](../004-den-spike/definition.md)
— the `jj` family, then the `llm` family, then the personal-data folder, then `ssh-access`. A
host-level clone starts only when the aspect coverage makes it cheap. Read this file to answer
"how much is left, and in what order", not "what do I do today".

Goal: reproduce the real macOS workstation as a den host, so the den aspect tree meets a real
machine instead of a sample. The clone is **build-only**. It never activates.

**Masked names.** This document writes `<fork-host>` for the real workstation's short name and
`<fork-only module>` for a module that lives on the fork chain only. Both hide employer-specific
data. Public short host names (`anji`, `moss`, `oams`, `brys`, `etra`) stay plain.

## Three scope rules

1. **Public chain only.** A fork-only piece gets a row marked `skip`, with `<fork-only module>` as
   its source and one clause of reason. No real path, no employer name.
2. **Capabilities, not identity.** The clone reproduces what the machine can do. It carries none of
   the creator's data. Each personal value becomes an aspect option with a neutral default, and the
   entity passes a neutral placeholder. The aspect declares the option; the consumer passes the
   value.
3. **Additive.** `modules/slots/`, `modules/universal/` and `modules/meta/` stay untouched. No live
   host imports den.

## One aspect per concern

A reusable den aspect has **no `enable` option**. Inclusion in the aspect list is the switch. So an
adopter opts out of a concern only when that concern is its own aspect.

The rule follows: **one aspect per concern, never a bundle.** An external adopter must be able to
skip Homebrew. The same holds for anything a developer likely owns already — the shell, the
editor, the terminal, the language toolchains. Homebrew becomes its own aspect, and its taps, casks
and formulas come from consumer options, so no adopter inherits the creator's taps.

The `Bundled?` column of the map flags every place where the current tree mixes concerns that den
must split. The five biggest offenders:

| Bundle | Concerns mixed in one merge |
|---|---|
| `modules/universal/default.nix` darwin block | Homebrew stack, host names, terminfo, a desktop default, root-user fixes |
| `profile/machine/baseline` | 12 unrelated `kdn.*` enables, plus an unconditional personal-user enable |
| `profile/machine/dev` | 18 language and tool enables behind one switch |
| `headless/base` | 11 enables, plus the shell, the terminal and the editor |
| `profile/user/kdn` | identity, git, gpg, browsers, secrets and packages in one module |

## §1 The capability map

48 rows. One row per capability the host provides, including a capability that needs no work.
`Class` uses den's names: `darwin`, `nixos`, `homeManager`, `devenv`. Note the rename — a slot
target is `home`; the den class is `homeManager`.

`New?` values: `exists` (ported already), `grow` (aspect exists, needs one more class), `new`,
`skip` (out of the public chain), `n/a` (not a darwin capability).

| Capability | Source module | den aspect | New? | Class | Personal value → option | Bundled? | Batch |
|---|---|---|---|---|---|---|---|
| Host entity, system, `stateVersion` | `hosts/<fork-host>/default.nix` | entity file | exists | darwin | none | no | B1 |
| home-manager on darwin | `modules/universal/default.nix` | den battery | exists | homeManager | none | no | B1 |
| Rosetta linux builder | `slots/rosetta-builder` | `kdn.rosetta-builder` | exists | darwin | none | no | B1 |
| FIDO2 ssh-agent replacement | `slots/ssh-agent` | `kdn.ssh-agent` | exists | homeManager | none | no | B1 |
| devenv CLI and shell hooks | `slots/devenv` | `kdn.devenv-cli` | exists | darwin, homeManager, devenv | none | no | B1 |
| GitHub CLI | `slots/gh` | `kdn.gh` | exists | devenv | none | no | B1 |
| MCP gateway | `slots/mcp` | `kdn.mcp` | exists | devenv | none | no | B1 |
| MCP knowledge bases | `slots/mcp/basic-memory` | `kdn.mcp-basic-memory` | exists | devenv | knowledge paths → options | no | B1 |
| MCP pretty print | `slots/mcp/pretty-print` | `kdn.mcp-pretty-print` | exists | devenv | none | no | B1 |
| MCP traffic snoop | `slots/mcp/snoop` | `kdn.mcp-snoop` | exists | devenv | none | no | B1 |
| opencode agent | `slots/opencode` | `kdn.opencode` | exists | devenv | none | no | B1 |
| jj VCS setup | `slots/jj` | `kdn.jj` | exists | devenv | remote names → options | no | B1 |
| jj fork workflow | `slots/jj/fork` | `kdn.jj-fork` | exists | devenv | remote names → options | no | B1 |
| CA trust | `slots/ca` | `kdn.ca` | exists | devenv | extra CA files → option | no | B1 |
| Primary user, uid, home dir | `profile/user/kdn` | `kdn.user` | new | darwin, homeManager | user name, uid → `kdn.user.name`, `kdn.user.uid` | yes | B2 |
| `home.sessionPath` entries | `profile/machine/baseline` | `kdn.user` | new | homeManager | none | yes | B2 |
| Nix daemon settings, substituters | `universal/nix/**`, `baseline` | `kdn.nix` | grow | darwin | none | yes | B3 |
| Automatic Nix GC | `profile/machine/baseline` | `kdn.nix-gc` | new | darwin | schedule → option | yes | B3 |
| zellij multiplexer | `headless/base` | `kdn.zellij` | grow | homeManager | theme, scrollback → options | yes | B3 |
| fish shell and auto attach | `headless/base` | `kdn.fish` | new | homeManager | none | yes | B3 |
| wezterm terminal | `headless/base` | `kdn.wezterm` | new | homeManager | key map → default | yes | B3 |
| Default editor | `headless/base` | `kdn.editor` | new | homeManager | editor name → option | yes | B3 |
| XDG user directories | `profile/machine/baseline` | `kdn.xdg` | new | homeManager | directory names → options | yes | B3 |
| terminfo entries | `universal/default.nix` darwin | `kdn.terminfo` | new | darwin | none | yes | B4 |
| Homebrew taps, casks, formulas | `universal/default.nix` darwin | `kdn.homebrew` | new | darwin | taps, casks → options | yes | B4 |
| `computerName`, `localHostName` | `universal/default.nix` darwin | `kdn.hostname` | new | darwin | host name → option | yes | B4 |
| root user shell and home fix | `universal/default.nix` darwin | `kdn.darwin-root` | new | darwin | none | yes | B4 |
| Locale and time zone | `universal/locale` | `kdn.locale` | new | darwin, homeManager | locale, timezone → options | no | B4 |
| sudo policy | `headless/base` | `kdn.sudo` | new | darwin | none | yes | B4 |
| Split-DNS resolver files | `hosts/<fork-host>/default.nix` | `kdn.split-dns` | new | darwin | zone FQDN, nameserver → `kdn.split-dns.zones` | no | B4 |
| git identity and credential helper | `profile/user/kdn` | `kdn.git` | new | homeManager | name, email, forge user → options | yes | B5 |
| Commit signing and the route switch | `slots/signing` | `kdn.signing` | new | homeManager | signer key, principal → options | no | B5 |
| angrr retention sweep | `profile/machine/baseline` | `kdn.angrr` | new | darwin | none | yes | B6 |
| openssh server | `profile/machine/baseline` | `kdn.openssh` | new | darwin | authorized keys → option | yes | B6 |
| SSH access topology dispatcher | `slots/ssh-access` | `kdn.ssh-access` | new | homeManager | host graph, identity file → options | no | B6 |
| Managed directory cleanup | `universal/managed` | `kdn.managed-dirs` | new | darwin, homeManager | directory list → option | no | B6 |
| `/run/configs` permission fix | `profile/machine/baseline` | `kdn.managed-dirs` | new | darwin | path list → option | yes | B6 |
| App directory and persistence lists | `universal/apps` | `kdn.apps` | new | homeManager | none | no | B6 |
| sops secret discovery | `security/secrets/sops` | `kdn.secrets` | new | darwin | sops folder → option | no | B7 |
| Language toolchains | `profile/machine/dev` | one aspect per language | new | homeManager | none | yes | B8 |
| Network toolset | `toolset/network` | `kdn.toolset-network` | new | darwin | none | yes | B8 |
| GUI applications | `universal/default.nix`, `desktop/**` | `kdn.gui-apps` | new | darwin | app list → option | yes | B8 |
| Theming and wallpaper | `universal/_stylix.nix` | `kdn.theme` | new | darwin, homeManager | wallpaper URL → option | no | out (§4) |
| `/etc/kdn/source-flake` tree copy | `profile/machine/baseline` | none — drop it | skip | — | whole-tree store copy | yes | out (§4) |
| gpg keys and the `pass` credential helper | `profile/user/kdn` | none | skip | — | personal key material | yes | out (§4) |
| Employer git auth and signing | `<fork-only module>` | none | skip | — | employer tooling | — | out (§4) |
| Employer machine profile | `<fork-only module>` | none | skip | — | employer policy | — | out (§4) |
| Disks, boot, kernel, ZFS | `disks/**`, `hw/**` | — | n/a | nixos | — | — | §5 |

## §2 The batches

8 batches. A batch lands together and ends in one build attempt. The order puts dependency first
and risk second: a batch that needs a new den mechanism comes after a batch that needs none.

Every build command below assumes the entity name `workstation-darwin` under a new
`checks/den-mvp/` sibling directory.

### B1 — the host shell (no new mechanism)

Aspects: `kdn.rosetta-builder`, `kdn.ssh-agent`, `kdn.devenv-cli`, `kdn.gh`, `kdn.nix`, `kdn.ca`,
`kdn.zellij`, `kdn.opencode`, `kdn.jj`, `kdn.jj-fork`, and the four `kdn.mcp*` aspects.

Mechanism: none new. `checks/den-mvp/host-darwin` already proves the shape. The devenv-only aspects
arrive through `den.policies.host-to-devenv`.

Proof: `nix build '.#denConfigurations.workstation-darwin.system'`

Failure if the mechanism is missing: the build succeeds and the shell holds nothing, because
`den.lib.aspects.resolve` returns an empty `imports` list for a whole-aspect function. The
`resolve` guard in `modules/den/lib.nix` turns that silence into a throw.

### B2 — the user split

Aspects: `kdn.user`.

Mechanism: the **double include**. A den user's `classes` defaults to `[ "user" ]` and omits
`homeManager` (`<den>/nix/lib/entities/host.nix:157`). An aspect with a `homeManager` target must
appear twice — once in the host aspect, once in the user aspect — and the user needs
`classes = [ "user" "homeManager" ]`.

Proof: `nix build '.#denHomeConfigurations.workstation-darwin-dev.activationPackage'`

Failure if missing: the `homeManager` target drops with no warning, and the home generation holds
none of the user's files.

### B3 — the shell, the terminal, the editor, the base tools

Aspects: `kdn.fish`, `kdn.wezterm`, `kdn.editor`, `kdn.xdg`, `kdn.nix-gc`, plus a `homeManager`
target on `kdn.zellij` and a `darwin` target on `kdn.nix` and `kdn.ca`.

Mechanism: none new. This batch is the first real test of the one-aspect-per-concern rule, because
it splits `headless/base` into four aspects.

Proof: `nix build '.#denConfigurations.workstation-darwin.system'`, then
`nix eval '.#denHomeConfigurations.workstation-darwin-dev.config.programs.fish.enable'`

Failure if missing: an option collision between two aspects that both write
`programs.fish.shellInit`. den's diamond dedupe collapses a shared parent to one import, so a
collision here means a real conflict, not a duplicate import.

### B4 — the darwin platform block, split

Aspects: `kdn.homebrew`, `kdn.hostname`, `kdn.terminfo`, `kdn.darwin-root`, `kdn.locale`,
`kdn.sudo`, `kdn.split-dns`.

Mechanism: **a Homebrew aspect** (§3, gap 1). The aspect file takes `nix-homebrew` in its own
arguments and closes over it, because a target module must not take `inputs`.

Proof: `nix eval '.#denConfigurations.workstation-darwin.config.homebrew.taps'`, then
`nix build '.#denConfigurations.workstation-darwin.system'`

Failure if missing: `The option 'nix-homebrew' does not exist` at evaluation, because no den
battery imports `nix-homebrew.darwinModules.nix-homebrew`.

### B5 — VCS identity and signing

Aspects: `kdn.git`, `kdn.signing`.

Mechanism: none new. Both are pure option work: a key, a principal and an email become options with
neutral defaults.

Proof: `nix eval '.#denHomeConfigurations.workstation-darwin-dev.config.programs.git.settings'`

Failure if missing: nothing fails; a personal value leaks into the aspect default. Read the
evaluated value and check it holds the placeholder.

### B6 — the housekeeping set

Aspects: `kdn.angrr`, `kdn.openssh`, `kdn.managed-dirs`, `kdn.apps`, `kdn.ssh-access`.

Mechanism: **a cross-aspect option merge.** `kdn.apps.<name>.dirs` receives entries from several
aspects. den keys each target module per aspect, so a diamond collapses to one import and a child
aspect writes the parent's option directly. No new mechanism, but the batch depends on B2 for the
user, and `kdn.ssh-access` depends on task 009 for its host graph.

Proof: `nix eval '.#denConfigurations.workstation-darwin.config.launchd.daemons' --apply 'builtins.attrNames'`

Failure if missing: `kdn.apps` declares its option twice and the evaluation fails with a duplicate
declaration error.

### B7 — secrets

Aspects: `kdn.secrets`.

Mechanism: **a sops-nix darwin battery of our own** (§3, gap 2).

Proof: `nix eval '.#denConfigurations.workstation-darwin.config.sops.secrets' --apply 'builtins.attrNames'`

Failure if missing: `The option 'sops' does not exist`. den ships no sops battery — a grep for
`sops` over den's `modules` and `nix` trees returns no match.

### B8 — the optional workstation surface

Aspects: one aspect per language toolchain, `kdn.toolset-network`, `kdn.gui-apps`.

Mechanism: none new. Volume only, and every aspect here is optional for an adopter. This batch
proves the rule works at scale: `profile/machine/dev` holds 18 enables behind one switch, and each
becomes its own aspect.

Proof: `nix build '.#denConfigurations.workstation-darwin.system'`

Failure if missing: nothing fails. A bundle survives review and an adopter cannot skip one
language.

## §3 Mechanism gaps

The four to examine first are Homebrew, home-manager on darwin, secrets and theming. Two are real
gaps in scope, one is not a gap at all, and one stays out.

### Gap 1 — Homebrew. Real gap, in scope.

Must do: declare a `kdn.homebrew` darwin aspect that imports
`nix-homebrew.darwinModules.nix-homebrew`, and expose `taps`, `casks` and `brews` as consumer
options with empty defaults. Keep `mutableTaps = false`, `trusted = true` and
`HOMEBREW_READ_ONLY=1`.

Nearest thing today: the darwin block of `modules/universal/default.nix` builds `nix-homebrew.taps`
from every flake input named `brew-tap--*` (8 such inputs), and derives `homebrew.taps` from them.

Difficulty: low. The mechanism is one import plus three options; the work is the tap-from-input
rule, which must become an explicit option instead of an input scan.

### Gap 2 — secrets. Real gap, in scope, last.

Must do: declare a `kdn.secrets` darwin aspect that imports `sops-nix.darwinModules.default` and
carries the file-discovery option surface.

Nearest thing today: `modules/universal/security/secrets/sops/default.nix`. Its **darwin-only block
is empty** ("nothing required for now"), so the darwin port is the discovery surface plus the module
import and little else. The `.allowed` guard is the kill switch that lets the tree evaluate with no
personal folder.

Difficulty: medium. The option surface reads sops YAML metadata rather than an explicit list, so
the aspect must keep that read lazy and keep the kill switch.

### Not a gap — home-manager on darwin.

den's home-manager battery resolves the module by class:

```nix
getModule = { host, ... }: inputs.home-manager."${host.class}Modules".home-manager;
```

For a darwin host that gives `darwinModules.home-manager`. `checks/den-mvp/host-darwin` already
builds one home generation with `users.dev.classes = [ "user" "homeManager" ]`. So no work is
needed here. The only trap is the **scope split** of B2: the user `classes` default omits
`homeManager`.

### Gap 3 — theming. Real gap, out of scope.

Must do: a `kdn.theme` aspect that imports `stylix.darwinModules.stylix` and exposes the image as an
option.

Nearest thing today: `modules/universal/_stylix.nix`. It sets `stylix.enable = true` unconditionally
and defaults `stylix.image` to a wallpaper URL on the creator's own cloud — tier-2 personal data in
task 009.

Difficulty: low to build, but it is the weakest scope candidate. Theming changes no capability of a
build-only clone, and it adds a personal value with no adopter benefit. Keep it out (§4).

### Gap 4 — the whole-tree store copy. A defect, not a gap.

`profile/machine/baseline` writes `environment.etc."kdn/source-flake".source = kdnConfig.self`. A
den evaluation never reads `self`, which is exactly why Pattern V1 holds for den. Do not port this.
Task 011 removes it from the existing tree.

### Gap 5 — the nixos disk and boot layer. Real gap, §5 only.

A darwin class hides disks, boot, the kernel and ZFS. The three follow-on hosts expose all four.
den ships no disko battery, so a `kdn.disks` aspect must import `disko.nixosModules.disko` itself.
Difficulty: medium for the import, high for the option surface, because a disk layout is
per-machine data.

## §4 What stays out

| Piece | Reason |
|---|---|
| `<fork-only module>` machine profile | employer policy; fork chain only |
| `<fork-only module>` password-manager git auth and signing | employer tooling; fork chain only |
| Employer Homebrew taps and formulas | employer-specific; an adopter must never inherit them |
| The employer email principal in `allowedSigners` | employer identity |
| The two split-DNS zone values on the real host | homelab FQDNs; the aspect keeps the option, the entity passes a placeholder |
| `profile/user/kdn` identity data | real name, email, forge user names, gpg keys, `authorized_keys`, u2f parts, browser profiles, password-store path, `initialHashedPassword`, uid — no clean option boundary |
| Theming and the wallpaper URL | §3 gap 3; changes no capability, adds a personal value |
| `/etc/kdn/source-flake` | a whole-tree store copy; task 011 removes it |
| The `desktop/**` tree | Linux only; a darwin host reaches almost none of it |

## §5 Three follow-on NixOS hosts, and the parity check

Order: the darwin workstation first, then `moss`, then `oams`, then `brys`. All three are
`moduleType: nixos` and `system: x86_64-linux`. All four clones are **build-only**. None ever
activates.

Each host below gets a delta against the darwin map, not a second full map.

### `moss` — the smallest delta

`hosts/moss/default.nix` is 41 lines.

- Capabilities the darwin clone does not cover: a boot loader, a kernel package set, a root
  filesystem, `networking.hostName` and DHCP.
- den aspects only a NixOS host needs: `kdn.boot`, `kdn.kernel`, `kdn.fs-root`, `kdn.networking`.
- Mechanism gaps a `nixos` class exposes: §3 gap 5, in its cheapest form — a plain single-disk
  layout with no disko file.

Use `moss` to prove the `nixos` class end to end. It is the only host here whose delta fits one
batch.

### `oams` — the microvm host

`hosts/oams/` holds `default.nix` (324 lines), `devenv.nix` (84) and `disko.nix` (171), with
`features.microvm-host: true`.

- Extra capabilities: a declarative disko layout, ZFS datasets and a persistence split, a microvm
  host role, guest definitions, and a per-host devenv shell.
- Extra aspects: `kdn.disks` with a real layout option, `kdn.zfs`, `kdn.persistence`,
  `kdn.microvm-host`.
- Extra gaps: the disko import (§3 gap 5) and a **feature-flag replacement**. `kdnConfig.features`
  has no den equivalent, and it needs none — a feature flag becomes aspect membership. Say so in the
  aspect, so nobody re-adds a flag.

### `brys` — the largest delta

`hosts/brys/` holds `default.nix` (470 lines), `devenv.nix` (113), `llm-minimal.nix` (315) and a
`certs/` directory.

- Extra capabilities: local LLM serving with a proxy and a client, per-service certificates, and
  more networking than any other host here.
- Extra aspects: the `llm` family (order 8 in the 004 table, 1,287 LOC, `nixos` plus `devenv`), plus
  `kdn.certs`.
- Extra gaps: none new beyond `oams`, but the `llm` port is the single largest remaining aspect
  group, and its `domain` value is a homelab FQDN that must become an option.

### The parity check

**`drvPath` equality will NOT hold between a den host and the matching existing configuration.**
The module structure differs, so Pattern V1 does not apply here. Do not spend a run on it. Pattern
V1 still holds *inside* the den route — between `denLib.imports` and the `flakeModule` route — and
that is a different comparison.

Compare capabilities instead. For each command below, `signal` means a difference is a real defect;
`noise` means a difference is expected and tells you nothing.

**Run this one first. It catches the most, and it costs one evaluation per side.** Compare the
evaluated package name sets:

```bash
nix eval --json '.#denConfigurations.workstation-darwin.config.environment.systemPackages' \
  --apply 'ps: builtins.sort (a: b: a < b) (map (p: p.name or "?") ps)' > /tmp/parity-den.json
nix eval --json '.#darwinConfigurations.anji.config.environment.systemPackages' \
  --apply 'ps: builtins.sort (a: b: a < b) (map (p: p.name or "?") ps)' > /tmp/parity-old.json
diff <(jq -r '.[]' /tmp/parity-old.json) <(jq -r '.[]' /tmp/parity-den.json)
```

A clean result is an empty `diff`, or a `diff` whose every line you can name and justify — a
package the clone drops on purpose, or a version move you expect. **Signal.**

The rest, in cost order:

| Comparison | Command shape | Verdict |
|---|---|---|
| Service name sets | `nix eval … .config.launchd.daemons --apply 'builtins.attrNames'` (darwin), `.config.systemd.services` (nixos) | signal |
| Users and uids | `nix eval --json … .config.users.users --apply 'us: builtins.mapAttrs (_: u: u.uid) us'` | signal |
| `/etc` file name set | `nix eval … .config.environment.etc --apply 'builtins.attrNames'` | signal |
| Home package name set | `nix eval … .config.home.packages --apply 'map (p: p.name)'` on each home configuration | signal |
| Mount points | `nix eval … .config.fileSystems --apply 'builtins.attrNames'` | signal, nixos only |
| Kernel version | `nix eval --raw … .config.boot.kernelPackages.kernel.version` | signal, nixos only |
| Networking values | `nix eval --json … .config.networking --apply 'n: { inherit (n) hostName; firewall = n.firewall.allowedTCPPorts; }'` | signal |
| Closure content | `nix store diff-closures <old-toplevel> <den-toplevel>` | signal for a missing package or a version move; noise for size deltas under a few MB |
| Derivation structure | `nix-diff <old-drv> <den-drv>` | noise until every name set above agrees; then it answers "why" |
| `drvPath` equality | — | **noise. It always differs. Do not run it.** |

`nix store diff-closures` needs both `system.build.toplevel` paths, so it needs two real builds. Run
it only after the name-set diffs are clean, because a name-set diff finds the same defect for a
fraction of the cost.

**Prerequisite risk for the three NixOS hosts.** This machine is `aarch64-darwin`. An
`x86_64-linux` build needs a working Linux builder here. A prior run found the rosetta-builder guest
blocked by a stale DNS proxy, so the builder is not dependable today. Fix the builder before any
`moss`, `oams` or `brys` batch starts. Treat the fix as a hard prerequisite, not a step of the port.
This document builds nothing.

## Exit criteria

1. The map holds a row for every capability of the real workstation, and every `skip` row names a
   reason.
2. Each batch ends in one build attempt whose command is written down.
3. Every personal value in the map has a named option with a neutral default.
4. No aspect bundles two concerns that an adopter would want to split.
5. The parity method runs the name-set diff first, and it never depends on `drvPath` equality.
