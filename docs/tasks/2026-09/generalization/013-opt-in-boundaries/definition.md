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

So a plain `= true` is the hard case. `modules/universal/profile/` held **65** of them when this
task started, measured with `grep -c 'kdn\..*\.enable = true;'` across that tree. **The same grep
prints 3 comment lines and no real site on 2026-09-11** — section 2 item 5 records the sweep.

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

> **Anchors re-measured 2026-09-11.** These moved, and the rows below still hold the old value:
> row 27 `modules/universal/default.nix:189` → `:191`;
> row 34 `:95-106` → `:96`;
> row 36 `profile/machine/baseline/default.nix:60` → option `:30`, guard `:115`, assignment `:116`;
> row 47 `modules/slots/jj/default.nix:132` → `:169`;
> row 53 `modules/slots/jj/default.nix:88-92` → `:125,129`, and `modules/den/aspects/jj.nix:79` → `:80`;
> row 63 `modules/slots/nix/default.nix:124-126` → `:160-162`.

| Item | File:line | Verdict (own aspect / option / mandatory) | Bundled? | In den today? | Closest-to-current option shape | Effort |
|---|---|---|---|---|---|---|
| 1. Homebrew turns on for every Darwin host that sets `kdn.enable` | `modules/universal/default.nix:202,204,216` | own aspect | yes — one `mkIf cfg.enable` block also holds `networking`, `nix.gc` and the tap wiring | **shipped 2026-09-11**: `kdn.homebrew.enable`, default **false**. `modules/universal/_options.nix` declares it. The darwin block of `modules/universal/default.nix` sets `lib.mkDefault true`, so `anji` and every other darwin host of this repository keep today's value. An adopter writes a plain `false`. | `kdn.homebrew.enable`, default false | M |
| 2. The tap wiring forces every `brew-tap--*` flake input | `modules/universal/default.nix:249` | own aspect (same switch as row 1) | yes | **partly shipped 2026-09-11**: `kdn.homebrew.enable` now gates the tap scan too, so an adopter drops it with one `false`. The attribute set of taps stays open — section 3 item 3 owns it. | an attribute set of taps, default empty | S |
| 3. 6 of 8 `brew-tap--*` inputs use `git+ssh://`, so a machine with no key stops | `flake.nix` — 8 tap `url` lines, 6 of them `git+ssh` (organisation name masked) | option | no | den needs no scan — `modules/den/aspects/homebrew.nix:49` declares `kdn.homebrew.taps`, default empty. **Fixed for the fetch 2026-09-11**: `kdn.homebrew.tapsFromFlakeInputs` defaults to false and `lib.mkIf` guards the scan, so no `git+ssh://` fetch reaches an adopter at `nix flake lock` or at `nix eval`. Measured on a cold tree with unreachable tap URLs — see section 2 item 3. The 8 lock nodes stay in the adopter's lock; section 3 item 3 owns that. | the tap set becomes a consumer value, so the inputs leave `flake.nix` | M |
| 4. Podman on Darwin needs Homebrew | `modules/universal/virtualisation/containers/podman/default.nix:27` | own aspect | yes — the container runtime and Homebrew share one switch | no | `kdn.virtualisation.containers.podman.darwin.viaHomebrew`, default false | S |
| 5. The browser launcher installs Homebrew casks | `modules/universal/programs/browsers-launcher/default.nix:34` | own aspect | no | no | an attribute set of casks, default empty | S |
| 6. fish, zsh and atuin turn on for every host with the baseline | `modules/universal/headless/base/default.nix:61-73` (atuin `:63`, fish `:64`, zsh `:65`) | own aspect | yes — one `mkIf` block sets 12 plain enables | **partly shipped 2026-09-11**: all 13 plain enables of that block are now `lib.mkDefault true`, so an adopter opts out per item with a plain `false`. A separate `enable` per shell stays open. | one `enable` per shell, default false | M |
| 7. fish becomes the login shell | `modules/universal/headless/base/default.nix:74` | option | yes (row 6) | no | `kdn.programs.fish.defaultShell`, default false | S |
| 8. zellij turns on in home-manager | option `modules/universal/headless/base/default.nix:31-36`, guard `:80` | own aspect | yes (row 6) | **shipped 2026-09-11**: `kdn.headless.base.zellij.enable`, default true. The bundle scope is deliberate — `headless/base` forwards its whole `cfg` into Home Manager as one `lib.mkDefault`, so a `kdn.programs.*` name would tie at priority 1000 and conflict. The `zellij` aspect still covers the devenv target only. | `kdn.programs.zellij.enable`, default false | S |
| 9. vim installs and takes `defaultEditor` | option `modules/universal/headless/base/default.nix:37-42`, guard `:156` | own aspect | yes (row 6) | **shipped 2026-09-11**: `kdn.headless.base.vim.enable`, default true. Same bundle scope, same reason as row 8. | `kdn.programs.vim.enable`, default false | S |
| 10. helix takes `defaultEditor` with a plain assignment | `modules/universal/programs/terminal-ide/default.nix:65` | option | yes — the editor and the language servers share one switch | **shipped 2026-09-11**: the line reads `programs.helix.defaultEditor = lib.mkDefault true`. The next line, `programs.vim.defaultEditor = false`, stays plain on purpose: `modules/universal/headless/base/default.nix:158` already writes `lib.mkDefault true` to that option, so a second `lib.mkDefault` holds the other value at priority 1000 and the evaluation stops. | `lib.mkDefault true` | XS |
| 11. A wezterm key-binding config lands in the home directory | option `modules/universal/headless/base/default.nix:43-48`, guard `:140` | own aspect | yes (row 6) | **shipped 2026-09-11**: `kdn.headless.base.wezterm.enable`, default true. Same bundle scope, same reason as row 8. Another module also writes `programs.wezterm.extraConfig`, so the switch removes this block's part only. | `kdn.programs.wezterm.enable`, default false | S |
| 12. gnupg also turns on `pass` | `modules/universal/programs/gnupg/default.nix:53` | own aspect | yes — the agent, the pinentry and the password manager share one switch | no | `kdn.programs.gnupg.passwordStore.enable`, default false | S |
| 13. The basic profile turns gnupg on with a plain assignment | `modules/universal/profile/machine/basic/default.nix:24` | option | yes (row 12) | **already fixed**: the profile sweep of section 2 item 5 reached this line. It reads `kdn.programs.gnupg.enable = lib.mkDefault true`. | `lib.mkDefault true` | XS |
| 14. gnupg force-disables gnome-keyring | `modules/universal/programs/gnupg/default.nix:113-114` | option | yes (row 12) | **shipped 2026-09-11**: `kdn.programs.gnupg.disableGnomeKeyring`, default true, guards both lines through a `lib.mkIf`. The two `lib.mkForce false` assignments stay inside the guard, because a desktop module turns gnome-keyring on and only a force beats it. | `kdn.programs.gnupg.disableGnomeKeyring`, default true | XS |
| 15. The signing key file name carries the creator's initials | `modules/slots/signing/default.nix:81` | option | no | **the aspect exists now** — `modules/den/aspects/signing.nix`, registered at `modules/den/lib.nix`. The default still carries the initials, so the row stays open on its own merits. | no default, or `~/.ssh/id_ed25519_signing` | XS |
| 16. The dev profile turns podman and the container stack on with plain assignments | `modules/universal/profile/machine/dev/default.nix:48-49` | own aspect | yes — 17 toolchains and the runtime share one profile | **shipped 2026-09-11**: `kdn.profile.machine.dev.containers.enable`, default true, gates the runtime alone. Every assignment in the profile is already `lib.mkDefault`. | `lib.mkDefault true` | XS |
| 17. 17 language toolchains turn on with one profile | `modules/universal/profile/machine/dev/default.nix:26-43` | own aspect | yes | **partly shipped 2026-09-11**: `kdn.profile.machine.dev.languages.enable`, default true, drops all 18 toolchains at once, and `desktop.enable` drops the desktop pull. One aspect per language stays open for the den port. | keep `mkDefault`; give each language its own aspect | M |
| 18. stylix turns on with no `kdn.*` switch at all | `modules/universal/_stylix.nix:37` | own aspect | yes — the theme, the fonts and the cursor share one file | no | `kdn.stylix.enable`, default false | M |
| 19. The wallpaper comes from the creator's own Nextcloud share | `modules/universal/_stylix.nix:39-44` (FQDN masked) | option | yes (row 18) | no | `stylix.image` with no default; the consumer supplies it | S |
| 20. Fira Code becomes the monospace font, and two font packages install system-wide | `modules/universal/_stylix.nix:52-53,96-99` | option | yes (row 18) | no | `fonts.packages` follows `stylix.fonts`, and holds no literal | S |
| 21. The X11 keyboard layout is `pl` | `modules/universal/profile/machine/desktop/default.nix:125` | option | no | **shipped 2026-09-11**: the line reads `services.xserver.xkb.layout = config.kdn.locale.xkbLayout;`. The option sits at `modules/universal/locale/default.nix:34-37`. Section 2 item 7 decided the `"pl"` default stays on purpose, so the adopter overrides one option. | `kdn.locale.xkbLayout` | XS |
| 22. The sway keyboard layout is `pl` | `modules/universal/desktop/sway/home-manager/default.nix:256` | option | no | **shipped 2026-09-11**: the line reads `xkb_layout = config.kdn.locale.xkbLayout;`, the same option as row 21. | the same option as row 21 | XS |
| 23. The time zone defaults to one European city | `modules/universal/locale/default.nix:22-26` | option — **[009](../009-personal-data-folder/definition.md) tier 2 owns it** | no | **the target shape is refuted 2026-09-11.** The type must stay `str`. The comment at `modules/universal/locale/default.nix:14-21` records why: the Home Manager branch writes `kdn.env.variables.TZ`, and `kdn.env.variables` has type `attrsOf str`, so a `null` stops every Home Manager evaluation. Section 2 item 7 decided this. | keep `str`; the adopter changes the value | XS |
| 24. Two Polish locales sit in the default list | `modules/universal/locale/default.nix:52-53` | option — **009 tier 2 owns it** | no | no | the list loses the language-specific entries. The `pl` short code now lives at `kdn.locale.xkbLayout` (`modules/universal/locale/default.nix:34-37`), which rows 21 and 22 own. | XS |
| 25. 14 desktop modules turn on together | `modules/universal/profile/machine/desktop/default.nix:37-50` | own aspect | yes | **partly shipped 2026-09-11**: all 14 lines read `lib.mkDefault true`, so an adopter opts out per item with a plain `false`. The bundle itself stays whole — section 3 item 1 owns it. | `lib.mkDefault` on each | S |
| 26. Chrome, Chromium, Firefox, Thunderbird and KDEConnect all install together | `modules/universal/profile/machine/desktop/default.nix:37-50` | own aspect | yes (row 25) | **partly shipped 2026-09-11**: each line is `lib.mkDefault true` already, so the per-item opt-out works. A separate `enable` per browser stays open. | one `enable` per browser, each `mkDefault` | S |
| 27. `kdn.desktop.enable` defaults to true on every Darwin host | `modules/universal/default.nix:189` | option | no | no | `lib.mkDefault false` | XS |
| 28. CUPS also declares one named printer and its LAN address | `modules/universal/services/printing/default.nix:67-76` | option — **009 tier 2 owns it** | yes — the daemon and the printer share one switch | no | `hardware.printers` moves to the consumer; default empty | S |
| 29. Samba defaults to a home-LAN CIDR and a personal workgroup name | `modules/universal/services/samba/default.nix:17,42` | option | no | no | `hostsAllow` drops the CIDR; `workgroup` becomes an option | XS |
| 30. `kdn.nixConfig` was `readOnly`, so no adopter assignment reached the whole nix policy | `modules/universal/_options.nix:31-33` (the removal note sits at `:24-29`) | option | yes — `nix.extraOptions`, `nix.settings` and `nixpkgs.config` share one value | **shipped 2026-09-11**: `readOnly` is gone. The option is a plain attribute set with today's value as the default. | drop `readOnly`; keep today's value as the default | S |
| 31. `allowUnfree = true` for every host | `modules/universal/nix.nix:48`, declared at `modules/universal/_options.nix:41` | option | yes (row 30) | **shipped 2026-09-11**: `kdn.nixpkgs.allowUnfree` exists. It defaults to `true`, so this repository keeps today's value; an adopter writes a plain `false`. | `kdn.nixpkgs.allowUnfree`, default false | XS |
| 32. Four insecure packages are permitted globally, for three personal applications | `modules/universal/nix.nix:52`, declared at `modules/universal/_options.nix:56` | option | yes (row 30) | **shipped 2026-09-11**: `kdn.nixpkgs.permittedInsecurePackages` exists, and `nix.nix:52` reads it. | `permittedInsecurePackages`, default empty | XS |
| 33. Three cachix substituters and their public keys apply to every host; a list merge cannot remove one | `modules/universal/nix.nix:39-40`, declared at `modules/universal/_options.nix:77` | option | yes (row 30) | **shipped 2026-09-11**: `kdn.nix.substituters` exists, and `nix.nix:39-40` reads it together with `trusted-public-keys`. | a list option, default empty | XS |
| 34. Lix replaces the nix package with a plain assignment | `modules/universal/default.nix:95-106` | option | no | **shipped 2026-09-11**: `nix.package = lib.mkDefault (…)`. No other module of this tree writes `nix.package`, so a consumer keeps CppNix with a plain assignment. | `lib.mkDefault` | XS |
| 35. `!include /etc/nix/nix.sensitive.conf` and one access-token file | `modules/universal/nix.nix:12-17` | **mandatory** — a `!include` with the leading `!` never fails on a missing file, so it is already adopter-safe | no | no | keep | n/a |
| 36. The baseline profile turns the creator's own user on | `modules/universal/profile/machine/baseline/default.nix:60` (the brief said 59) | option — **009 hard blocker 1 owns it** | yes — the baseline also sets `kdn.enable`, the locale and the headless base | **partly shipped 2026-09-11**: `kdn.profile.machine.baseline.primaryUser.enable`, default true, drops the user without touching the locale or the headless base. 009 hard blocker 1 still owns the end state, a baseline with no user at all. | no user at all; the host names its own | M |
| 37. One sops file path is hardwired at three sites | `modules/universal/profile/default-secrets/default.nix:21,25,85` | option — **[008](../008-sops-default-inventory/definition.md) and 009 own it** | yes | no | `sopsFile` per secret, default null | M |
| 38. A real root password hash and a real initrd emergency hash | `modules/universal/profile/machine/baseline/default.nix:198,245` | option — **009 tier 3 owns it** | no | no | no default; the host supplies both | S |
| 39. A 55-line `ssh_known_hosts` fleet file loads for every NixOS host | `modules/universal/profile/machine/baseline/default.nix:322` | option — **009 tier 3 owns it** | no | no | `knownHostsFiles`, default empty | XS |
| 40. The creator's checkout path is hardwired at three sites | `modules/universal/development/nix/default.nix:27`, `modules/universal/profile/machine/baseline/default.nix:360-361` | option | yes — the option default reads `kdn.profile.user.kdn.homeDir`, so it needs the creator's user module | **partly shipped 2026-09-11**: `kdn.profile.machine.baseline.flakeCheckoutLinks.enable` drops the three tmpfiles links. Its default follows `primaryUser.enable`, because the link target reads the primary user's home directory. `kdn.development.nix.flake.path` stays open. | `kdn.development.nix.flake.path`, default null; skip the tmpfiles link when null | S |
| 41. Four named overlay network clients turn on with the baseline | `modules/universal/profile/machine/baseline/default.nix:369-375` | option — **009 tier 3 owns it** | yes | **partly shipped 2026-09-11**: `kdn.profile.machine.baseline.overlayNetworks.enable`, default true, drops both overlay-network clients of this tree. The attribute set of clients stays with 009 tier 3. | an attribute set of clients, default empty | S |
| 42. The baseline also turns a Nextcloud desktop client on | `modules/universal/profile/machine/baseline/default.nix:377` | own aspect | yes | **shipped 2026-09-11**: `kdn.profile.machine.baseline.nextcloudClient.enable`, default true. It keeps the `kdn.security.secrets.allowed` condition, so today's value stays. | `lib.mkDefault false` | XS |
| 43. A personal Nextcloud share path appears in two modules | `modules/universal/profile/user/kdn/default.nix:11`, `modules/universal/programs/photoprism/default.nix:27` (FQDN masked) | option — **009 tier 3 owns it** | no | **partly shipped 2026-09-11**: `kdn.profile.user.kdn.nextcloud.enable`, default true, drops every consumer of the sync share in `profile/user/kdn` — the password-store link, the screenshot path and the password-manager search directory. The path itself stays with 009 tier 3. | the consumer supplies the path | S |
| 44. 176 LOC of host graph, LAN addresses, WAN ports and homelab zones | `data/slots-ssh-access.nix` (every FQDN masked) | option — **[007](../007-depersonalize-slots/definition.md) item 5 and 009 tier 3 own it** | no | no aspect — `ssh-access` is unported | the graph is already a consumer value; only the file moves | S |
| 45. 5 slots install agent rules and skills into the adopter repo; `kdn.isSourceRepo` is the only switch | `modules/slots/jj/default.nix:23,61,213`, `modules/slots/jj/fork/default.nix:267`, `modules/slots/nix/default.nix:22,134`, `modules/slots/zellij/default.nix:56,125`, `modules/slots/mcp/basic-memory/default.nix:23,140` | option — **007 item 4 owns the slot half** | no longer — one switch per slot covers the opinion, and the tool stays | **fixed on both routes** — `modules/den/aspects/jj.nix:112,277`, `jj-fork.nix:157,432`, `nix.nix:97,223`, `zellij.nix:98,160`, `mcp-basic-memory.nix:172,257` | **shipped**: `kdn.<name>.installAgentRules`, default **false** (section 3 item 4, candidate A). The 3 consumers set it true: `devenv.nix:54-58`, `checks/den-mvp/devenv/default.nix:120-124`, `checks/den-mvp/host-darwin/default.nix:52` | S |
| 46. The `jj` slot also registers a proactive `jj-expert` subagent | `modules/slots/jj/default.nix:204`, and `modules/den/aspects/jj.nix:270` | option | no longer (row 45) | **fixed on both routes** — the same switch as row 45 gates the subagent | **shipped**: `kdn.jj.installAgentRules`, default false | XS |
| 47. Four slots turn Claude Code on; `jj` uses a plain assignment | `modules/slots/gh/default.nix:89`, `modules/slots/zellij/default.nix:65`, `modules/slots/nix/default.nix:37`, `modules/slots/jj/default.nix:132` | option | yes | **shipped 2026-09-11**: every slot writes `lib.mkDefault true` now. `jj`, `nix` and `mcp/pretty-print` were the three plain sites; `gh` and `zellij` already used a default. Two identical `lib.mkDefault true` definitions merge, because `types.bool` accepts equal values. | `lib.mkDefault true` everywhere | XS |
| 48. The mcp snoop slot defaults to on, against this repo's own side-effect-free rule | `modules/slots/mcp/snoop/default.nix:19` | own aspect | no | **fixed on both routes** — the `mcp-snoop` aspect carries no `enable`, and the slot option is now `lib.mkEnableOption`, so it defaults to false | `lib.mkEnableOption` | XS |
| 49. The mcp pretty-print slot defaults to on, for the same reason | `modules/slots/mcp/pretty-print/default.nix:104` | own aspect | no | **fixed on both routes** — `mcp-pretty-print` carries no `enable`, and the slot option is now `lib.mkEnableOption` | `lib.mkEnableOption` | XS |
| 50. The mcp gateway forces four backends | `modules/slots/mcp/default.nix:132-136` | option | yes | **shipped 2026-09-11** on the slot route: all five lines read `lib.mkDefault`, `filesystem.args` included. Measured with `lib.evalModules`: an `attrsOf anything` option carries the priority to every leaf, so a consumer drops one backend with a plain `false`. The den aspect (`modules/den/aspects/mcp.nix:207-211`) still holds the plain form. | `lib.mkDefault` on each | XS |
| 51. The `nix` slot forces one MCP program and one extra backend | `modules/slots/nix/default.nix:24-29` | option | yes — nix tooling and the MCP gateway share one switch | **shipped 2026-09-11** on the slot route: one `lib.mkDefault` per leaf — `programs.nixos.enable`, `extraBackends.devenv.command`, `.description` and `.env.DEVENV_ROOT`. A `lib.mkDefault` on the whole stanza is wrong here: a consumer who repoints one field then loses the other two, because the higher-priority definition replaces the set. The den aspect (`modules/den/aspects/nix.nix:134-135`) still holds the plain form. | `lib.mkDefault` | XS |
| 52. The `nix` slot freezes this repository's own checkout into the devenv MCP backend | `modules/slots/nix/default.nix:28` | **mandatory to fix** — an adopter's backend points at the wrong tree | no | **fixed** — `modules/den/aspects/nix.nix:84-87` reads `DEVENV_ROOT` at run time | n/a | XS |
| 53. The `jj` slot writes two MCP settings, and turns the git backend off | `modules/slots/jj/default.nix:88-92` | option | yes | **stronger in den** — `modules/den/aspects/jj.nix:79` puts `kdn.mcp` in the aspect's own `includes`, so `jj` pulls the whole gateway | `lib.mkDefault`, plus a bool to skip the coupling | S |
| 54. `opencode` hardwires one commercial provider at three sites | `modules/slots/opencode/default.nix:103,105,140` | own aspect — **007 item 1 owns it** | yes — the wrapper and the provider share one switch | **fixed** — the aspect declares `authKeys` and `settings`, and names no provider | a provider sub-option, default off | S |
| 55. `opencode` allows `~/dev/**` in five permission blocks | `modules/slots/opencode/default.nix:51,55,59,63,67` | option — **007 item 2 owns it** | no | **fixed** — `modules/den/aspects/opencode.nix:153` defaults to `[ "/nix/store/**" ]` | a path list, default `[ "/nix/store/**" ]` | XS |
| 56. `kdn.jj.upstream.remote` defaults to a personal remote name | `modules/slots/jj/default.nix:31` | option — **007 item 2 owns it** | no | **fixed** — `modules/den/aspects/jj.nix:113` defaults to `"origin"` | `"origin"` | XS |
| 57. `kdn.jj.alwaysBlockedMessagePatterns` defaults to one personal word | `modules/slots/jj/default.nix:25` | option — **007 item 2 owns it** | no | **fixed** — `modules/den/aspects/jj-fork.nix:26-27` defaults to the empty list | the empty list, after the 001 loud-failure fix lands | XS |
| 58. `llm` option examples hold homelab FQDNs and two overlay addresses | `modules/slots/llm/default.nix:432,449-451,461-463`, `modules/slots/llm/client/default.nix:77` (FQDNs masked) | option — **007 item 2 owns it**, and its line numbers are one off from mine | no | no aspect — `llm`, `llm/client` and `llm/proxy` are unported | a neutral example | XS |
| 59. `basic-memory` hardwires two knowledge-base names and two aliases | `modules/slots/mcp/basic-memory/default.nix:10-17` | option | no | **fixed** — the aspect declares `knowledgeRoot` and `bases`, and `mcp-basic-memory.nix:174` defaults to a neutral path | an attribute set of bases, default empty | S |
| 60. The `ca` slot example names `kdnConfig.self`, a universal special argument | `modules/slots/ca/default.nix:74-75` | option — **007 item 2 owns it** (doc-only) | no | the `ca` aspect holds no such example | a neutral example | XS |
| 61. The `devenv` slot writes a shell hook for bash, zsh and fish together | `modules/slots/devenv/default.nix:40-48` | option | yes | **closed 2026-09-11, no defect**: a measurement enabled bash only, with zsh and fish off, and read `{"fishFileExists":false,"zshFileExists":false}`. home-manager writes an init file only for a shell the consumer turns on, so the shared hook block reaches no disabled shell. The `devenv-cli` aspect covers this slot and needs no change either. | no change — a per-shell bool buys nothing | XS |
| 62. The `devenv` slot writes `keep-outputs` and `keep-derivations` as free-form text | `modules/slots/devenv/default.nix:25-28` | **mandatory** — devenv holds its garbage-collector roots through both settings | no | `devenv-cli` | keep | n/a |
| 63. The `nix` slot leaves a `hello` script that names this repository | `modules/slots/nix/default.nix:124-126` | option | no | **fixed** — `modules/den/aspects/nix.nix:52` records the removal | remove the script | XS |
| 64. `toolset/essentials` names four personal tool choices in one package list | `modules/universal/toolset/essentials/default.nix:26-27,37,55` | own aspect | yes — 20 packages share one switch | no | split the list per concern | S |
| 65. difftastic gets a dark background with a plain assignment | `modules/universal/toolset/essentials/default.nix:61-62` | option | yes (row 64) | **shipped 2026-09-11**: both lines read `lib.mkDefault`, so a consumer drops difftastic or picks a light background. | `lib.mkDefault` | XS |
| 66. The ssh-agent slot permanently disables the macOS built-in agent for the user | `modules/slots/ssh-agent/default.nix:59-60` | **mandatory** — the slot exists for this, and its own `enable` already gates it | no | the `ssh-agent` aspect | n/a | n/a |

## Section 2 — the ranked first cuts

Eight items, ranked by adopter value against effort. Each line names the change and one command
that proves it.

1. **fixed 2026-09-10** — both mcp children now default to false, and `devenv.nix` sets both true.
   Rows 48 and 49. This was the only place the repository broke its own written rule.
   `d630e819 refactor(slots/mcp): make the snoop and pretty-print children opt-in` did the flip:
   each option is now `lib.mkEnableOption`, not a `default = true`. `devenv.nix:71-72` restores the
   two `true` values, so this repository's behaviour stays identical. The `templates/adopter`
   example dropped its two `false` lines on 2026-09-11, because they are no-ops now.
   Measured on 2026-09-11 with `devenv eval 'claude.code.mcpServers.mcp-gateway.command'`:
   with `snoop.enable = true` the command is `…-mcp-gateway-snoop-wrapper`; with `false` it is
   `…-mcp-gateway-wrapper`, so the wrapper leaves. With `pretty-print.enable = false` the hook
   `claude.code.hooks.mcp-gateway-pretty-print` is absent.

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

3. **fixed 2026-09-11 for the fetch; the lock text stays with section 3 item 3.** Rows 2 and 3.
   `kdn.homebrew.tapsFromFlakeInputs` now defaults to **false** (`modules/universal/_options.nix:142`),
   and the flake-input scan sits behind `lib.mkIf cfg.homebrew.tapsFromFlakeInputs`
   (`modules/universal/default.nix:247`). `hosts/anji/default.nix:42` sets it true, so `anji` keeps
   today's 8 taps.
   **Measured on 2026-09-11**, from a scratch adopter flake in `/tmp` that imports
   `nix-configs.darwinModules.default` with the flake's own `kdnMetaModule` special arguments and
   assigns **nothing** to `kdn.homebrew.*`. Every `nix eval` ran with `--no-eval-cache` under
   `SSH_AUTH_SOCK=` and a `GIT_SSH_COMMAND` wrapper that logs each attempt:
   `nix-homebrew.taps` → `[ ]`, `homebrew.taps` → `[ ]`, `homebrew.casks` → `[ ]`,
   `homebrew.brews` → `[ ]`, `kdn.homebrew.tapsFromFlakeInputs` → `false`. Zero ssh attempts.
   A warm store could hide a fetch, so the run repeated on a cold copy: a `git archive HEAD` tree
   in `/tmp` with the 6 `git+ssh` tap URLs repointed at an unreachable
   `git+ssh://git@127.0.0.1:2222/nope-N`. At the defaults the evaluation exits 0 with `[ ]` and no
   ssh attempt. With `tapsFromFlakeInputs` forced true the same tree fails on
   `git+ssh://…/nope-1` and the ssh log records the attempt. So the switch stops the fetch, not a
   cache.
   **Three costs, measured separately.** (a) Lock text — **real and unavoidable**: the adopter's
   own `flake.lock` inherits all 8 `brew-tap--*` nodes, 109 nodes in total. (b) Fetch at
   `nix flake lock` — **none**. (c) Fetch at `nix eval` of the Darwin config — **none** at the
   defaults. Only (a) remains, and section 3 item 3 candidate B owns it: it needs the user's
   decision, because it removes the inputs from `flake.nix`.
   One fact this row does **not** cover: an adopter's `kdn.homebrew.enable` still evaluates to
   `true`, because the darwin block sets `lib.mkDefault true`. Row 1 designed that on purpose — an
   adopter opts out with a plain `false`.

4. **shipped 2026-09-11** — `readOnly` is gone from `kdn.nixConfig`, and all three narrow options
   exist. Rows 30 to 33. `modules/universal/_options.nix:31-33` declares `nixConfig` plain, and
   the comment at `:24-27` records the removal. The three options are
   `kdn.nixpkgs.allowUnfree` (`_options.nix:41`), `kdn.nixpkgs.permittedInsecurePackages`
   (`:56`) and `kdn.nix.substituters` (`:77`). `modules/universal/nix.nix:48`, `:52` and
   `:39-40` read them. Section 3 item 6 now needs a ratify-or-revert, not a design.

5. **fixed 2026-09-11** — the profile tree holds **no** plain `kdn.*.enable = true` any more, and
   the same shape now carries `lib.mkDefault` at 16 more sites outside the profile tree. Rows 6, 9,
   10, 13, 14, 16, 25, 26, 34, 42, 47, 50, 51 and 65.

   **The profile sweep itself landed before this batch.** Commits `59297fe8`, `85cc3df9`, `57be8246`
   and `d54b45a9` did it. Measured on 2026-09-11 at `b0e8f3d4`:
   `grep -rn 'kdn\..*\.enable = true;' modules/universal/profile/` prints **3** lines and all three
   are comments. `grep -rn 'enable = lib.mkDefault true;' modules/universal/profile/` prints **131**
   lines, **97** of them a `kdn.*` option. The 29 remaining `= true;` lines of that tree are not
   opt-out sites: 12 are option declarations (`default = true`, `readOnly = true`), and the rest are
   nixpkgs user attributes (`isNormalUser`, `createHome`, `isHidden`, `isSystemUser`), nix settings
   (`keep-booted-system`, `keep-current-system`), `inheritParentConfig`, `pyproject` and one
   `serviceConfig.RemainAfterExit`.

   **This batch converted 16 assignments in 7 files**, every one an XS row of the same shape:
   `programs/terminal-ide/default.nix` 1 site (row 10), `universal/default.nix` 1 site (row 34),
   `toolset/essentials/default.nix` 2 sites (row 65), `slots/jj/default.nix` 1 site,
   `slots/mcp/pretty-print/default.nix` 1 site and `slots/nix/default.nix` 1 site (row 47),
   `slots/mcp/default.nix` 5 sites (row 50), `slots/nix/default.nix` 4 more sites (row 51).
   An eighth file takes a different route: `programs/gnupg/default.nix` (row 14) gains
   `kdn.programs.gnupg.disableGnomeKeyring`, default `true`, and puts the two `lib.mkForce false`
   lines behind `lib.mkIf`. A `lib.mkForce` stays forced; the new option is the opt-out path.

   Rows 50 and 51 use a `lib.mkDefault` **per leaf**, not one on the whole stanza. Three
   `lib.evalModules` tests measured why: `attrsOf anything` carries the priority down to every leaf,
   and a `lib.mkDefault` on a whole attrset makes a partial plain override drop the siblings.

   **Two sites stay plain, and each reason is a measured module-system fact.**
   `programs/terminal-ide/default.nix:66` writes `programs.vim.defaultEditor = false` while
   `headless/base/default.nix:158` writes `lib.mkDefault true` to the same option. A second
   `lib.mkDefault` ties at priority 1000 with a different value, so the evaluation stops.
   `slots/jj/default.nix:129` writes `kdn.mcp.programs.git.enable = false`; row 53 owns that line,
   because the fix needs a bool to skip the coupling, not a priority change.

   **Two more XS rows look like this shape and are not.** Row 27 asks for `lib.mkDefault false` on
   `kdn.desktop.enable`; the line is already `lib.mkDefault true`, so the open part is a **value**
   flip that every Darwin host must then answer. Row 52 asks to unfreeze
   `extraBackends.devenv.env.DEVENV_ROOT`; the `lib.mkDefault` of row 51 gives an adopter the
   override, but the run-time read of `DEVENV_ROOT` stays with row 52.

   **Verification.** `drvPath` equality proves nothing in this tree, because `kdnConfig.self`
   reaches the evaluated config and every edit therefore moves every host path. This batch used an
   option-value probe instead: each touched option path, host-side and per Home Manager user, on
   the pristine `b0e8f3d4` and on the dirty tree, with `--no-eval-cache`.
   **Result on 2026-09-11:** 15 hosts, 609 leaf values compared, **0 differ**. The single change is
   the new `disableGnomeKeyring` option, absent on the pristine reference and `true` on the dirty
   tree, on every host. `nix flake check --no-eval-cache` exits **0** with 125 pytest tests passed.
   `toplevel.drvPath` was forced on **3 hosts only** — `brys`, `oams` and one darwin host — because
   the force proves nothing but that the evaluation completes, and the per-host option probe plus
   `nix flake check` already prove that. The formatter reindented **0 lines**: `git diff --stat` and
   `git diff -w --stat` agree at 8 `.nix` files, 46 insertions, 21 deletions.
   See the worklog of this directory for the command list.

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

   **What landed deviates from this text on two points, and the deviation is deliberate.**
   `kdn.locale.xkbLayout` exists (`modules/universal/locale/default.nix:34-37`) and both consumers
   read it — `profile/machine/desktop/default.nix:125` and
   `desktop/sway/home-manager/default.nix:256`. So one edit now changes the layout of both trees,
   which was the point of the row. But:
   - The default is `"pl"`, not `"us"`. A `modules/universal` option serves **16 host directories**
     of this repository. A neutral default flips the value for each host that wants the personal
     one, so the flip is 15 more consumer edits, not one. [009](../009-personal-data-folder/definition.md)
     owns the personal-data folder, and that folder is where the personal value belongs. Rows 21 and
     22 stay open for 009.
   - `kdn.locale.timezone` keeps the literal `"Europe/Warsaw"` and the type stays `str`, not
     `nullOr str`. A `null` time zone **stops the evaluation**: the Home Manager branch writes
     `kdn.env.variables.TZ = cfg.timezone` (`modules/universal/locale/default.nix:115`) and
     `kdn.env.variables` has type `attrsOf str` (`modules/universal/env/default.nix:54-55`). So a
     `nullOr` default needs a guard in the Home Manager branch first. That is 009 tier 2 work, and
     row 23 already names 009 as the owner. The module carries this reason as a comment.

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

   **The `lib.mkDefault` sweep of section 2 item 5 does not answer this item either, and the status
   stays `DECISION TO REVISE`.** A priority change makes candidate A workable — an adopter opts out
   of one item with a plain assignment — but it argues for neither candidate. Candidate B asks
   whether a profile stays one bundle or becomes a list of aspects, and no priority answers that
   question. Row 25 keeps 14 desktop modules in one file, and row 64 keeps 20 packages in one list.
   Both rows are unchanged in shape; only the priority moved.

2. `DECISION TO REVISE` — **Does `stylix` keep a whole-tree switch, or does theming become one
   aspect?** Row 18. Candidate A: add `kdn.stylix.enable`, default false, and leave
   `_stylix.nix` in place. Candidate B: move the file to an aspect, so a host that names no theme
   aspect never evaluates stylix.

3. `DECISION TO REVISE` — **Does the tap set stay a flake input pattern, or become a plain
   option?** Row 3. Candidate A: keep `brew-tap--*` inputs, and gate the whole block, so an
   adopter with no tap pays only lock text. Candidate B: replace the pattern with
   `kdn.homebrew.taps`, an attribute set of paths, so the inputs leave `flake.nix` and the
   adopter's lock loses 8 nodes.

   **Candidate A already shipped, and a measurement on 2026-09-11 narrowed this question.** The
   gate exists: `kdn.homebrew.tapsFromFlakeInputs`, default false, at
   `modules/universal/_options.nix:142` and `modules/universal/default.nix:247`. An adopter at the
   defaults now pays **lock text only** — no `git+ssh://` fetch happens at `nix flake lock` or at
   `nix eval` of a Darwin host, proved on a cold tree with 6 unreachable tap URLs. So the open
   question is no longer "does an adopter with no key stop?"; it is only "do the 8 inherited lock
   nodes justify the move to candidate B?". The den route already answers candidate B for itself:
   `modules/den/aspects/homebrew.nix:49` declares `kdn.homebrew.taps` with an empty default and
   reads no flake input.

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
  flip needed no new option, and it **landed on 2026-09-10** in commit `d630e819`.

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

**Re-measured 2026-09-11.** The den registry holds **20** aspects
(`modules/den/lib.nix:36-56`). `modules/slots/` holds **19** slot `default.nix` files besides
the loader, and **every one has an aspect**. The extra aspect is `homebrew`, which no slot
covers.

So no row now waits on milestone 2. Rows 15, 44 and 58 are open on their own merits, not for
want of an aspect.

## Exit criteria

- Every row in section 1 reaches a state: fixed, deferred to a named checkpoint, or answered in
  section 3.
- Pattern V1 holds for each fix that claims to be a no-op.
- Pattern V2 passes for rows 1 to 3, with no SSH agent and no usable key.
- `nix run .#kdn-nix-fmt --` is clean.
