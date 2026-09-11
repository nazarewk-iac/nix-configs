---
type: Task
status: open
description: An evidence-based inventory of everything an external adopter wants to turn off and today cannot, with a verdict per item.
timestamp: 2026-09-10T21:00:00+02:00
authored_by: agent
---

# 013 — opt-in boundaries

Hub: [../definition.md](../definition.md). Number 013 was free, so this task uses it. A concurrent
agent took 012 during this work.

Goal: name every item an **external adopter** wants to switch off and today cannot. Each row
carries a verdict, and each verdict says where the value belongs. No row redesigns a mechanism.

## The one decision this task owns

The user granted exactly one decision domain: **the boundary of personal-scoped configuration
inputs**. So a row decides *where a value belongs*. A row never decides *how a mechanism gets
rebuilt*. Section 3 lists every question that crosses that line.

The trigger was Homebrew. A developer who already runs Homebrew must be able to not configure it.
The same holds for the shell, the editor, the terminal, the language toolchains, a password
manager and a container runtime.

## The decision test

| Test | Verdict |
|---|---|
| A competent developer plausibly already owns this, or objects to it | **own aspect** — a den aspect has no `enable`, so inclusion in the aspect list is the switch. "Own aspect" and "opt-in" are the same thing. |
| The value is unique to one person, one machine or one organisation | **option** with a neutral default. The consumer passes the real value. |
| The tree breaks without it | **mandatory**, with the reason in one clause. |

A row is **bundled** when one module mixes several concerns, so an adopter cannot drop one part
and keep the rest. Bundled is the case that blocks a partial opt-out.

## Two module-system facts every row rests on

I measured both with `lib.evalModules` on 2026-09-10.

| Shape | Result when the adopter assigns `false` |
|---|---|
| `x.enable = true` (plain, priority 100) | **conflict** — the evaluation stops. The adopter needs `lib.mkForce`. |
| `x.enable = lib.mkDefault true` (priority 1000) | merges to `false`. The adopter opts out with a plain assignment. |
| `readOnly = true` on the option | **refused** — no assignment reaches it at all. |
| `types.listOf` | the two lists concatenate. The adopter adds an entry; the adopter cannot remove one. |

So a plain `= true` is the hard case. `modules/universal/profile/` holds **65** of them, measured
with `grep -c 'kdn\..*\.enable = true;'` across that tree.

## Effort scale

| Tag | Meaning |
|---|---|
| XS | one line, or a default value |
| S | one file, plus a default in this repo's own hosts |
| M | a new option plus a guard, across two or three files |
| L | a structural move |

## Masked content

I masked one organisation name, one personal Nextcloud FQDN and every homelab FQDN. Each row
cites the file and the line instead of the value. Short host names such as `anji` and `brys` stay
in plain text.

## Section 1 — the inventory

66 rows. Every row carries a measured `file:line`.

| Item | File:line | Verdict (own aspect / option / mandatory) | Bundled? | In den today? | Closest-to-current option shape | Effort |
|---|---|---|---|---|---|---|
| 1. Homebrew turns on for every Darwin host that sets `kdn.enable` | `modules/universal/default.nix:209,224` | own aspect | yes — one `mkIf cfg.enable` block also holds `networking`, `nix.gc` and the tap wiring | **shipped 2026-09-11**: `kdn.homebrew.enable`, default **false**. `modules/universal/_options.nix` declares it. The darwin block of `modules/universal/default.nix` sets `lib.mkDefault true`, so `anji` and every other darwin host of this repository keep today's value. An adopter writes a plain `false`. | `kdn.homebrew.enable`, default false | M |
| 2. The tap wiring forces every `brew-tap--*` flake input | `modules/universal/default.nix:227-243` | own aspect (same switch as row 1) | yes | **partly shipped 2026-09-11**: `kdn.homebrew.enable` now gates the tap scan too, so an adopter drops it with one `false`. The attribute set of taps stays open — section 3 item 3 owns it. | an attribute set of taps, default empty | S |
| 3. 6 of 8 `brew-tap--*` inputs use `git+ssh://`, so a machine with no key stops | `flake.nix` — 8 tap `url` lines, 6 of them `git+ssh` (organisation name masked) | option | no | no | the tap set becomes a consumer value, so the inputs leave `flake.nix` | M |
| 4. Podman on Darwin needs Homebrew | `modules/universal/virtualisation/containers/podman/default.nix:27` | own aspect | yes — the container runtime and Homebrew share one switch | no | `kdn.virtualisation.containers.podman.darwin.viaHomebrew`, default false | S |
| 5. The browser launcher installs Homebrew casks | `modules/universal/programs/browsers-launcher/default.nix:34` | own aspect | no | no | an attribute set of casks, default empty | S |
| 6. fish, zsh and atuin turn on for every host with the baseline | `modules/universal/headless/base/default.nix:31-33` | own aspect | yes — one `mkIf` block sets 12 plain enables | **partly shipped 2026-09-11**: all 13 plain enables of that block are now `lib.mkDefault true`, so an adopter opts out per item with a plain `false`. A separate `enable` per shell stays open. | one `enable` per shell, default false | M |
| 7. fish becomes the login shell | `modules/universal/headless/base/default.nix:41` | option | yes (row 6) | no | `kdn.programs.fish.defaultShell`, default false | S |
| 8. zellij turns on in home-manager | `modules/universal/headless/base/default.nix:48` | own aspect | yes (row 6) | **shipped 2026-09-11**: `kdn.headless.base.zellij.enable`, default true. The bundle scope is deliberate — `headless/base` forwards its whole `cfg` into Home Manager as one `lib.mkDefault`, so a `kdn.programs.*` name would tie at priority 1000 and conflict. The `zellij` aspect still covers the devenv target only. | `kdn.programs.zellij.enable`, default false | S |
| 9. vim installs and takes `defaultEditor` | `modules/universal/headless/base/default.nix:123-124` | own aspect | **shipped 2026-09-11**: `kdn.headless.base.vim.enable`, default true. Same bundle scope, same reason as row 8. | `kdn.programs.vim.enable`, default false | S |
| 10. helix takes `defaultEditor` with a plain assignment | `modules/universal/programs/terminal-ide/default.nix:65` | option | yes — the editor and the language servers share one switch | no | `lib.mkDefault true` | XS |
| 11. A wezterm key-binding config lands in the home directory | `modules/universal/headless/base/default.nix:107` | own aspect | **shipped 2026-09-11**: `kdn.headless.base.wezterm.enable`, default true. Same bundle scope, same reason as row 8. Another module also writes `programs.wezterm.extraConfig`, so the switch removes this block's part only. | `kdn.programs.wezterm.enable`, default false | S |
| 12. gnupg also turns on `pass` | `modules/universal/programs/gnupg/default.nix:53` | own aspect | yes — the agent, the pinentry and the password manager share one switch | no | `kdn.programs.gnupg.passwordStore.enable`, default false | S |
| 13. The basic profile turns gnupg on with a plain assignment | `modules/universal/profile/machine/basic/default.nix:24` | option | yes (row 12) | no | `lib.mkDefault true` | XS |
| 14. gnupg force-disables gnome-keyring | `modules/universal/programs/gnupg/default.nix:113-114` | option | yes (row 12) | no | `kdn.programs.gnupg.disableGnomeKeyring`, default true | XS |
| 15. The signing key file name carries the creator's initials | `modules/slots/signing/default.nix:82` | option | no | no aspect — `signing` is one of the 5 unported slots | no default, or `~/.ssh/id_ed25519_signing` | XS |
| 16. The dev profile turns podman and the container stack on with plain assignments | `modules/universal/profile/machine/dev/default.nix:48-49` | own aspect | yes — 17 toolchains and the runtime share one profile | **shipped 2026-09-11**: `kdn.profile.machine.dev.containers.enable`, default true, gates the runtime alone. Every assignment in the profile is already `lib.mkDefault`. | `lib.mkDefault true` | XS |
| 17. 17 language toolchains turn on with one profile | `modules/universal/profile/machine/dev/default.nix:26-43` | own aspect | yes | **partly shipped 2026-09-11**: `kdn.profile.machine.dev.languages.enable`, default true, drops all 18 toolchains at once, and `desktop.enable` drops the desktop pull. One aspect per language stays open for the den port. | keep `mkDefault`; give each language its own aspect | M |
| 18. stylix turns on with no `kdn.*` switch at all | `modules/universal/_stylix.nix:37` | own aspect | yes — the theme, the fonts and the cursor share one file | no | `kdn.stylix.enable`, default false | M |
| 19. The wallpaper comes from the creator's own Nextcloud share | `modules/universal/_stylix.nix:39-44` (FQDN masked) | option | yes (row 18) | no | `stylix.image` with no default; the consumer supplies it | S |
| 20. Fira Code becomes the monospace font, and two font packages install system-wide | `modules/universal/_stylix.nix:52-53,96-99` | option | yes (row 18) | no | `fonts.packages` follows `stylix.fonts`, and holds no literal | S |
| 21. The X11 keyboard layout is `pl` | `modules/universal/profile/machine/desktop/default.nix:125` | option | no | no | `kdn.locale.xkbLayout`, default `"us"` | XS |
| 22. The sway keyboard layout is `pl` | `modules/universal/desktop/sway/home-manager/default.nix:256` | option | no | no | the same option as row 21 | XS |
| 23. The time zone defaults to one European city | `modules/universal/locale/default.nix:17` | option — **[009](../009-personal-data-folder/definition.md) tier 2 owns it** | no | no | `null` default; skip `time.timeZone` when null | XS |
| 24. Two Polish locales and two Polish short codes sit in the default lists | `modules/universal/locale/default.nix:32-33,43-44` | option — **009 tier 2 owns it** | no | no | the lists lose the language-specific entries | XS |
| 25. 14 desktop modules turn on with plain assignments | `modules/universal/profile/machine/desktop/default.nix:37-50` | own aspect | yes | no | `lib.mkDefault` on each | S |
| 26. Chrome, Chromium, Firefox, Thunderbird and KDEConnect all install together | `modules/universal/profile/machine/desktop/default.nix:44-49` | own aspect | yes (row 25) | no | one `enable` per browser, each `mkDefault` | S |
| 27. `kdn.desktop.enable` defaults to true on every Darwin host | `modules/universal/default.nix:189` | option | no | no | `lib.mkDefault false` | XS |
| 28. CUPS also declares one named printer and its LAN address | `modules/universal/services/printing/default.nix:67-76` | option — **009 tier 2 owns it** | yes — the daemon and the printer share one switch | no | `hardware.printers` moves to the consumer; default empty | S |
| 29. Samba defaults to a home-LAN CIDR and a personal workgroup name | `modules/universal/services/samba/default.nix:17,42` | option | no | no | `hostsAllow` drops the CIDR; `workgroup` becomes an option | XS |
| 30. `kdn.nixConfig` is `readOnly`, so no adopter assignment reaches the whole nix policy | `modules/universal/_options.nix:20-23`, applied at `modules/universal/default.nix:110-112` | option | yes — `nix.extraOptions`, `nix.settings` and `nixpkgs.config` share one read-only value | no | drop `readOnly`; keep today's value as the default | S |
| 31. `allowUnfree = true` for every host | `modules/universal/nix.nix:42` | option | yes (row 30) | no | `kdn.nixpkgs.allowUnfree`, default false | XS |
| 32. Four insecure packages are permitted globally, for three personal applications | `modules/universal/nix.nix:44-49` | option | yes (row 30) | no | `permittedInsecurePackages`, default empty | XS |
| 33. Three cachix substituters and their public keys apply to every host; a list merge cannot remove one | `modules/universal/nix.nix:25-34` | option | yes (row 30) | no | a list option, default empty | XS |
| 34. Lix replaces the nix package with a plain assignment | `modules/universal/default.nix:95-106` | option | no | no | `lib.mkDefault` | XS |
| 35. `!include /etc/nix/nix.sensitive.conf` and one access-token file | `modules/universal/nix.nix:12-17` | **mandatory** — a `!include` with the leading `!` never fails on a missing file, so it is already adopter-safe | no | no | keep | n/a |
| 36. The baseline profile turns the creator's own user on | `modules/universal/profile/machine/baseline/default.nix:60` (the brief said 59) | option — **009 hard blocker 1 owns it** | yes — the baseline also sets `kdn.enable`, the locale and the headless base | **partly shipped 2026-09-11**: `kdn.profile.machine.baseline.primaryUser.enable`, default true, drops the user without touching the locale or the headless base. 009 hard blocker 1 still owns the end state, a baseline with no user at all. | no user at all; the host names its own | M |
| 37. One sops file path is hardwired at three sites | `modules/universal/profile/default-secrets/default.nix:21,25,85` | option — **[008](../008-sops-default-inventory/definition.md) and 009 own it** | yes | no | `sopsFile` per secret, default null | M |
| 38. A real root password hash and a real initrd emergency hash | `modules/universal/profile/machine/baseline/default.nix:198,245` | option — **009 tier 3 owns it** | no | no | no default; the host supplies both | S |
| 39. A 55-line `ssh_known_hosts` fleet file loads for every NixOS host | `modules/universal/profile/machine/baseline/default.nix:322` | option — **009 tier 3 owns it** | no | no | `knownHostsFiles`, default empty | XS |
| 40. The creator's checkout path is hardwired at three sites | `modules/universal/development/nix/default.nix:27`, `modules/universal/profile/machine/baseline/default.nix:360-361` | option | yes — the option default reads `kdn.profile.user.kdn.homeDir`, so it needs the creator's user module | **partly shipped 2026-09-11**: `kdn.profile.machine.baseline.flakeCheckoutLinks.enable` drops the three tmpfiles links. Its default follows `primaryUser.enable`, because the link target reads the primary user's home directory. `kdn.development.nix.flake.path` stays open. | `kdn.development.nix.flake.path`, default null; skip the tmpfiles link when null | S |
| 41. Four named overlay network clients turn on with the baseline | `modules/universal/profile/machine/baseline/default.nix:369-375` | option — **009 tier 3 owns it** | yes | **partly shipped 2026-09-11**: `kdn.profile.machine.baseline.overlayNetworks.enable`, default true, drops both overlay-network clients of this tree. The attribute set of clients stays with 009 tier 3. | an attribute set of clients, default empty | S |
| 42. The baseline also turns a Nextcloud desktop client on | `modules/universal/profile/machine/baseline/default.nix:377` | own aspect | yes | **shipped 2026-09-11**: `kdn.profile.machine.baseline.nextcloudClient.enable`, default true. It keeps the `kdn.security.secrets.allowed` condition, so today's value stays. | `lib.mkDefault false` | XS |
| 43. A personal Nextcloud share path appears in two modules | `modules/universal/profile/user/kdn/default.nix:11`, `modules/universal/programs/photoprism/default.nix:27` (FQDN masked) | option — **009 tier 3 owns it** | no | **partly shipped 2026-09-11**: `kdn.profile.user.kdn.nextcloud.enable`, default true, drops every consumer of the sync share in `profile/user/kdn` — the password-store link, the screenshot path and the password-manager search directory. The path itself stays with 009 tier 3. | the consumer supplies the path | S |
| 44. 176 LOC of host graph, LAN addresses, WAN ports and homelab zones | `modules/slots/ssh-access/kdn-graph.nix` (every FQDN masked) | option — **[007](../007-depersonalize-slots/definition.md) item 5 and 009 tier 3 own it** | no | no aspect — `ssh-access` is unported | the graph is already a consumer value; only the file moves | S |
| 45. 5 slots install agent rules and skills into the adopter repo; `kdn.isSourceRepo` is the only switch | `modules/slots/jj/default.nix:23,61,213`, `modules/slots/jj/fork/default.nix:267`, `modules/slots/nix/default.nix:22,134`, `modules/slots/zellij/default.nix:56,125`, `modules/slots/mcp/basic-memory/default.nix:23,140` | option — **007 item 4 owns the slot half** | no longer — one switch per slot covers the opinion, and the tool stays | **fixed on both routes** — `modules/den/aspects/jj.nix:112,277`, `jj-fork.nix:157,432`, `nix.nix:97,223`, `zellij.nix:98,160`, `mcp-basic-memory.nix:172,257` | **shipped**: `kdn.<name>.installAgentRules`, default **false** (section 3 item 4, candidate A). The 3 consumers set it true: `devenv.nix:54-58`, `checks/den-mvp/devenv/default.nix:120-124`, `checks/den-mvp/host-darwin/default.nix:52` | S |
| 46. The `jj` slot also registers a proactive `jj-expert` subagent | `modules/slots/jj/default.nix:204`, and `modules/den/aspects/jj.nix:270` | option | no longer (row 45) | **fixed on both routes** — the same switch as row 45 gates the subagent | **shipped**: `kdn.jj.installAgentRules`, default false | XS |
| 47. Four slots turn Claude Code on; `jj` uses a plain assignment | `modules/slots/gh/default.nix:89`, `modules/slots/zellij/default.nix:65`, `modules/slots/nix/default.nix:37`, `modules/slots/jj/default.nix:132` | option | yes | den keeps `mkDefault` — `gh.nix:20`, `zellij.nix:102`, `nix.nix:126`, `jj.nix:198`. den already fixed the plain `jj` case. | `lib.mkDefault true` everywhere | XS |
| 48. The mcp snoop slot defaults to on, against this repo's own side-effect-free rule | `modules/slots/mcp/snoop/default.nix:18` | own aspect | no | **fixed** — the `mcp-snoop` aspect carries no `enable`, so inclusion is the switch | drop `default = true` | XS |
| 49. The mcp pretty-print slot defaults to on, for the same reason | `modules/slots/mcp/pretty-print/default.nix:103` | own aspect | no | **fixed** — `mcp-pretty-print` carries no `enable` | drop `default = true` | XS |
| 50. The mcp gateway forces four backends | `modules/slots/mcp/default.nix:132-136` | option | yes | **the port reproduces it** — `modules/den/aspects/mcp.nix:207-211` | `lib.mkDefault` on each | XS |
| 51. The `nix` slot forces one MCP program and one extra backend | `modules/slots/nix/default.nix:24-29` | option | yes — nix tooling and the MCP gateway share one switch | **reproduced** — `modules/den/aspects/nix.nix:114` | `lib.mkDefault` | XS |
| 52. The `nix` slot freezes this repository's own checkout into the devenv MCP backend | `modules/slots/nix/default.nix:28` | **mandatory to fix** — an adopter's backend points at the wrong tree | no | **fixed** — `modules/den/aspects/nix.nix:84-87` reads `DEVENV_ROOT` at run time | n/a | XS |
| 53. The `jj` slot writes two MCP settings, and turns the git backend off | `modules/slots/jj/default.nix:88-92` | option | yes | **stronger in den** — `modules/den/aspects/jj.nix:79` puts `kdn.mcp` in the aspect's own `includes`, so `jj` pulls the whole gateway | `lib.mkDefault`, plus a bool to skip the coupling | S |
| 54. `opencode` hardwires one commercial provider at three sites | `modules/slots/opencode/default.nix:103,105,140` | own aspect — **007 item 1 owns it** | yes — the wrapper and the provider share one switch | **fixed** — the aspect declares `authKeys` and `settings`, and names no provider | a provider sub-option, default off | S |
| 55. `opencode` allows `~/dev/**` in five permission blocks | `modules/slots/opencode/default.nix:51,55,59,63,67` | option — **007 item 2 owns it** | no | **fixed** — `modules/den/aspects/opencode.nix:153` defaults to `[ "/nix/store/**" ]` | a path list, default `[ "/nix/store/**" ]` | XS |
| 56. `kdn.jj.upstream.remote` defaults to a personal remote name | `modules/slots/jj/default.nix:31` | option — **007 item 2 owns it** | no | **fixed** — `modules/den/aspects/jj.nix:113` defaults to `"origin"` | `"origin"` | XS |
| 57. `kdn.jj.alwaysBlockedMessagePatterns` defaults to one personal word | `modules/slots/jj/default.nix:25` | option — **007 item 2 owns it** | no | **fixed** — `modules/den/aspects/jj-fork.nix:26-27` defaults to the empty list | the empty list, after the 001 loud-failure fix lands | XS |
| 58. `llm` option examples hold homelab FQDNs and two overlay addresses | `modules/slots/llm/default.nix:432,449-451,461-463`, `modules/slots/llm/client/default.nix:77` (FQDNs masked) | option — **007 item 2 owns it**, and its line numbers are one off from mine | no | no aspect — `llm`, `llm/client` and `llm/proxy` are unported | a neutral example | XS |
| 59. `basic-memory` hardwires two knowledge-base names and two aliases | `modules/slots/mcp/basic-memory/default.nix:10-17` | option | no | **fixed** — the aspect declares `knowledgeRoot` and `bases`, and `mcp-basic-memory.nix:174` defaults to a neutral path | an attribute set of bases, default empty | S |
| 60. The `ca` slot example names `kdnConfig.self`, a universal special argument | `modules/slots/ca/default.nix:74-75` | option — **007 item 2 owns it** (doc-only) | no | the `ca` aspect holds no such example | a neutral example | XS |
| 61. The `devenv` slot writes a shell hook for bash, zsh and fish together | `modules/slots/devenv/default.nix:40-48` | option | yes | the `devenv-cli` aspect covers this slot | one bool per shell, each default true | XS |
| 62. The `devenv` slot writes `keep-outputs` and `keep-derivations` as free-form text | `modules/slots/devenv/default.nix:25-28` | **mandatory** — devenv holds its garbage-collector roots through both settings | no | `devenv-cli` | keep | n/a |
| 63. The `nix` slot leaves a `hello` script that names this repository | `modules/slots/nix/default.nix:124-126` | option | no | **fixed** — `modules/den/aspects/nix.nix:52` records the removal | remove the script | XS |
| 64. `toolset/essentials` names four personal tool choices in one package list | `modules/universal/toolset/essentials/default.nix:26-27,37,55` | own aspect | yes — 20 packages share one switch | no | split the list per concern | S |
| 65. difftastic gets a dark background with a plain assignment | `modules/universal/toolset/essentials/default.nix:61-62` | option | yes (row 64) | no | `lib.mkDefault` | XS |
| 66. The ssh-agent slot permanently disables the macOS built-in agent for the user | `modules/slots/ssh-agent/default.nix:59-60` | **mandatory** — the slot exists for this, and its own `enable` already gates it | no | the `ssh-agent` aspect | n/a | n/a |

## Section 2 — the ranked first cuts

Eight items, ranked by adopter value against effort. Each line names the change and one command
that proves it.

1. **Flip the two default-on mcp slots to `default = false`, then set both true in this repo's own
   `devenv.nix`.** Rows 48 and 49. This is the only place the repository breaks its own written
   rule, and the den aspects already prove the shape works.
   `devenv eval 'claude.code.mcpServers.mcp-gateway.command'` — the snoop wrapper must leave the
   command when the option is false.

2. **fixed 2026-09-11** — Homebrew now sits behind `kdn.homebrew.enable`, default **false**. Rows 1
   and 2. This was the trigger for the whole task. A Darwin adopter who already runs Homebrew used
   to get a second, declarative Homebrew with `onActivation.cleanup = "zap"`.
   `modules/universal/_options.nix` declares the switch. The darwin block of
   `modules/universal/default.nix` sets `lib.mkDefault true`, so every darwin host of this
   repository keeps today's value and an adopter opts out with a plain `false`.
   Measured on `anji`: with the switch off, `homebrew.enable`, `nix-homebrew.enable` and the
   `HOMEBREW_READ_ONLY` shell export all leave, and nothing else moves.
   `nix eval --json '.#darwinConfigurations.anji.config.homebrew.enable'` — it must stay true for
   `anji`, because the darwin block sets the new option.

3. **Make the tap set a consumer attribute set, default empty.** Rows 2 and 3. It removes 6
   `git+ssh://` fetches from an adopter's Darwin build, and the hub already grades this as a real
   blocker on the fresh-guest path.
   `SSH_AUTH_SOCK= nix eval --json '.#darwinConfigurations.anji.config.nix-homebrew.taps' --apply builtins.attrNames`
   — Pattern V2 must reach a result with no key present.

4. **Drop `readOnly` from `kdn.nixConfig`, and give `allowUnfree`, `permittedInsecurePackages` and
   the substituter list neutral defaults.** Rows 30 to 33. `readOnly` refuses every assignment, so
   an adopter cannot state a nix policy at all. A list merge concatenates, so an adopter cannot
   remove a substituter either.
   `nix eval '.#nixosConfigurations.brys.options.kdn.nixConfig.readOnly'` — it must print `false`.

5. **Change every plain `= true` in `modules/universal/profile/` to `lib.mkDefault true`.** Rows
   6, 9, 13, 16, 25, 26 and 42, plus 58 more sites. One mechanical pass unlocks every opt-out in
   this table below the profile layer, and it changes no evaluated value.
   `nix eval --raw '.#nixosConfigurations.brys.config.system.build.toplevel.drvPath'` — Pattern
   V1, and the path must not change.

6. **fixed** — `installAgentRules` now exists on the 5 slots and the 5 den aspects that write
   `.claude/` files. Rows 45 and 46. An adopter who does not use `jj` never receives the jj mandate
   or the subagent. The default is **false**: section 3 item 4 picked candidate A. The 3 consumers
   in this repository set it true, so this repository's own behaviour stays identical.
   Measured on 2026-09-11. With the explicit `true`, the written file set, the subagent, the 5 Claude
   Code hooks, the 3 git hooks and the MCP server registration are byte-identical to `upstream-tip`
   (`57be824`) on both routes. With the default, all 10 instruction files leave and every functional
   file stays: `.mcp.json`, `.pre-commit-config.yaml` and `.claude/settings.json`.
   `nix eval --json '.#denDevenvShells.devenv-darwin.files' --apply builtins.attrNames` —
   every `.claude/rules/` entry there comes from an explicit `installAgentRules = true`.

7. **Add `kdn.locale.xkbLayout`, default `"us"`, and default the time zone to null.** Rows 21 to
   24. Two literals sit in two unrelated trees today, so a layout change needs two edits.
   `nix eval '.#nixosConfigurations.brys.config.services.xserver.xkb.layout'` — it must still read
   the personal value from the host.

8. **Copy the four defaults the den aspects already fixed back into the slots.** Rows 54 to 57.
   The aspect files hold the measured, de-personalized value, so each slot edit is a copy with no
   design work.
   `nix eval '.#denModules.jj' --apply 'm: builtins.length m.imports'` — the aspect route must stay
   non-empty while the two routes converge.

## Section 3 — what needs the user

Every item where the smallest safe change still needs a decision the user reserved.

1. `DECISION TO REVISE` — **Does a profile stay a bundle, or does it become a list of
   aspects?** Rows 6, 17, 25 and 64. Candidate A: keep the profile, and change 65 plain `= true`
   assignments to `mkDefault`, so an adopter opts out per item. Candidate B: split each profile
   into one aspect per concern, and let the adopter name the list.

   **Partial work landed on 2026-09-11, and it does not answer this question.** Five bundles now
   carry one sub-switch per concern: the darwin block of `modules/universal/default.nix`,
   `headless/base`, `profile/machine/dev`, `profile/machine/baseline` and `profile/user/kdn`. That
   is candidate A plus a group switch per concern. It is a **within-profile** split, so it adds no
   aspect and it removes no profile. Each profile still holds every concern.

   The session note `../.session-2026-09-10.md` records the five splits as approved under the
   delegated class, so the work went ahead. This item stays `DECISION TO REVISE`, because the
   aspect-versus-profile question is untouched. Rows 25 and 64 are also untouched.

2. `DECISION TO REVISE` — **Does `stylix` keep a whole-tree switch, or does theming become one
   aspect?** Row 18. Candidate A: add `kdn.stylix.enable`, default false, and leave
   `_stylix.nix` in place. Candidate B: move the file to an aspect, so a host that names no theme
   aspect never evaluates stylix.

3. `DECISION TO REVISE` — **Does the tap set stay a flake input pattern, or become a plain
   option?** Row 3. Candidate A: keep `brew-tap--*` inputs, and gate the whole block, so an
   adopter with no tap pays only lock text. Candidate B: replace the pattern with
   `kdn.homebrew.taps`, an attribute set of paths, so the inputs leave `flake.nix` and the
   adopter's lock loses 8 nodes.

4. `DECIDED 2026-09-11` — **Does an adopter get the agent rules by default, or never?** Rows 45
   and 46. Candidate A: `installAgentRules` defaults to false, so an adopter opts in. Candidate
   B: it defaults to true, and the docs say how to opt out — the rules carry real value, and a
   silent absence is its own surprise.
   **The user picked candidate A.** A slot has exactly one consumer in this repository, `devenv.nix`,
   so a neutral default costs 5 lines and no host edit. A neutral default is also the honest one: an
   adopter who uses plain git must not silently receive a rule that forbids raw `git`.
   The option exists on all 5 slots and all 5 aspects and defaults to `false`. This repository sets
   it true in `devenv.nix`, in `checks/den-mvp/devenv/default.nix` and in
   `checks/den-mvp/host-darwin/default.nix`, so its own behaviour stays identical. The option covers
   the instruction files only; every hook, allowlist, package and MCP registration stays
   unconditional.

5. `DECISION TO REVISE` — **Does `kdn.jj` keep the MCP coupling?** Row 53. The den aspect made it
   stronger: `modules/den/aspects/jj.nix:79` puts `kdn.mcp` in the aspect's `includes`, so `jj`
   now brings the whole gateway. Candidate A: keep the coupling, because the jj MCP backend is
   the point. Candidate B: split a `jj-mcp` aspect, so `jj` alone installs the CLI and the hook.

6. `DECISION TO REVISE` — **Does the nix policy stay one value, or split into three?** Row 30.
   Candidate A: drop `readOnly` and keep one `kdn.nixConfig` attribute set. Candidate B: split it
   into `nix.settings`, `nix.extraOptions` and `nixpkgs.config` options, each with its own neutral
   default.

7. `DECISION TO REVISE` — **Does the baseline profile keep any user at all?** Row 36. This is
   009's hard blocker 1, and 009 defers the mechanism to 006. Candidate A: the baseline declares
   no user, and every host names its own. Candidate B: the baseline takes a `primaryUser` option,
   and the personal data folder supplies the value.

8. `DECISION TO REVISE` — **Does the `kdn-` unit-name and env-var prefix stay?** 007 item 2 lists
   this and states no answer. Candidate A: keep the prefix, because a rename buys nothing —
   the hub's gap 10 already reaches that verdict for the option namespace. Candidate B:
   parametrize the prefix, so an adopter's units carry their own name.

## Section 4 — what stays

### Genuinely mandatory

| Item | File:line | Reason |
|---|---|---|
| `!include` of the sensitive nix config and the access-token file | `modules/universal/nix.nix:12-17` | The leading `!` makes the include optional, so a missing file never stops an evaluation. It is already adopter-safe. |
| `keep-outputs` and `keep-derivations` | `modules/slots/devenv/default.nix:25-28` | devenv holds its garbage-collector roots through both settings. Without them the collector deletes a live shell. |
| The macOS built-in ssh-agent goes away | `modules/slots/ssh-agent/default.nix:59-60` | The slot exists for this one effect, and the slot's own `enable` already gates it. The built-in agent cannot sign with a FIDO2 key. |
| `kdn.security.secrets.sops.files.<name>` discovery | see [008](../008-sops-default-inventory/definition.md) | 009 records this as the kill switch that makes the personal folder optional. Keep the mechanism; 008 lists the unguarded consumers. |
| The `kdn.*` option namespace | hub gap 10 | The hub decided against a rename. The churn buys nothing. |
| The `users` slot target | hub gap 11 | Unused today, and the hub decided to keep it. |

### Already owned by 007

Rows 44, 45, 46, 48, 49, 54, 55, 56, 57, 58 and 60 belong to
[007](../007-depersonalize-slots/definition.md), across its items 1 to 5. Row 15 does **not** — 007
item 2 lists five personal defaults, and the signing key file name is not one of them. This task
adds two more facts 007 does not hold:

- The den port **already fixed** rows 54 to 57 and row 59 in the aspect files. So each slot edit
  is a copy of a measured value, not a design step.
- Rows 48 and 49 are 007 item 3, and the den aspects prove the no-`enable` shape works. So the
  flip needs no new option.

### Already owned by 009

Rows 23, 24, 28, 36, 37, 38, 39, 41 and 43 belong to
[009](../009-personal-data-folder/definition.md), and 009's own tier tables list each one. This
task adds one fact 009 does not hold: row 40 couples an **option default** to the creator's user
module. `modules/universal/development/nix/default.nix:27` reads
`config.kdn.profile.user.kdn.homeDir`, so the default cannot evaluate once the user module leaves.
009's tier-2 table names the file but not the coupling.

### What this task alone holds

**43 of the 66 rows** have no owner in the checkpoint index today: 1 to 22, 25 to 27, 29 to 34, 40,
42, 47, 50 to 53, 59, 61 and 63 to 65. Three more rows (35, 62 and 66) are mandatory, and the
remaining 20 belong to 007, 008 or 009. So the four groups this task alone holds are the Homebrew
group, the shell and editor group, the nix-policy group and the MCP-coupling group.

## Coverage note

The den registry holds **14** aspects (`modules/den/lib.nix:36-50`). `modules/slots/` holds **19**
slot `default.nix` files besides the loader. Five slots have no aspect: `llm`, `llm/client`,
`llm/proxy`, `signing` and `ssh-access`. `modules/den/README.md:279` records the same 14-of-19
split, so the two trees agree.

So 5 slots carry rows that no aspect can fix yet: 15, 44 and 58. Those three wait on milestone 2.

## Exit criteria

- Every row in section 1 reaches a state: fixed, deferred to a named checkpoint, or answered in
  section 3.
- Pattern V1 holds for each fix that claims to be a no-op.
- Pattern V2 passes for rows 1 to 3, with no SSH agent and no usable key.
- `nix run .#kdn-nix-fmt --` is clean.
