---
type: Research
status: done
description: Per-area audit of modules/universal — declared option prefixes, real cross-area coupling, third-party imports, guard sites and remaining personal values — with a corrected batch order.
timestamp: 2026-09-11T12:00:00+02:00
authored_by: agent
---

# 014 step 1 — the per-area audit

Parent task: [definition.md](definition.md).

This file answers step 1 and step 2 of the task. Every number below comes from a `grep -rn
--include='*.nix'` run on 2026-09-11. Each non-obvious claim carries a `file:line` citation.

## Scope and exclusions

`modules/universal/` holds 23 shared areas, 6 root files, and **one machine-local area**. The
machine-local area is organisation-specific. This audit excludes it from every table. It holds
2 files, 150 lines, 4 `kdnConfig` references and 2 files that write `kdn.env.*`.

Three shared files are **in flux** — a concurrent editor writes them, so their state may move:
`_stylix.nix`, `default.nix`, `development/nix/`, `locale/`, `programs/photoprism/` and
`services/samba/`. Each table marks them.

## Method

| Measurement | Command shape |
|---|---|
| Files and lines | `find <area> -name '*.nix'`, then `cat` piped to `wc -l` |
| Declared prefixes | `grep -rho 'options\.kdn\.…'` plus `grep -A3 '^\s*options\s*=\s*{'` — the tree uses both forms, see `hw/qmk/default.nix:13-14` |
| Coupling | `grep -rn '\bkdn\.<segment>\b'`, with `pkgs.kdn.`/`lib.kdn.` filtered out |
| Reads | `grep -rn '\(config\|osConfig\)\.kdn\.<segment>\b'` |
| Guards | `grep -rnE 'util\.(ifTypes\|ifHM\|ifHMParent\|ifNotHMParent\|isOfType)'` versus `util\.(hasParentOfAnyType\|loadModules\|modules\|hasSops)` |

`n/f` means `n` references across `f` files.

## Table 1 — size, declared prefixes, personal values

| Area | Files | Lines | `kdnConfig` | Declared `kdn.*` prefixes | Personal value? | Option that holds it |
|---|---|---|---|---|---|---|
| `apps` | 1 | 163 | 5 | `kdn.apps` | NO | — |
| `desktop` | 17 | 2349 | 37 | `kdn.desktop.{base,kde,remote-server,sway}`, `kdn.desktop.enable` | NO | a public gist URL only, `desktop/sway/default.nix:260` |
| `development` | 30 | 1703 | 74 | 25 prefixes under `kdn.development.*` | NO (in flux) | `kdn.development.nix.flake.path` now defaults to `null`, `development/nix/default.nix:25-27` |
| `disks` | 2 | 1236 | 5 | `kdn.disks` | NO | a bare host name in a comment, `disks/config.nix:156-162` |
| `emulation` | 1 | 52 | 3 | `kdn.emulation.wine` | NO | — |
| `env` | 1 | 73 | 4 | `kdn.env.packages`, `kdn.env.variables` | NO | — |
| `fs` | 3 | 378 | 7 | `kdn.fs.{disko,watch,zfs}` | NO | — |
| `headless` | 1 | 280 | 6 | `kdn.headless.base` | NO | — |
| `helpers` | 1 | 79 | 2 | `kdn.helpers` | NO | — |
| `hw` | 17 | 1079 | 34 | `kdn.hw.{audio,basic,bluetooth,cpu,edid,gpu,intel-graphics-fix,modem,nanokvm,qmk,usbip,yubikey}` | **YES** | `hw/yubikey/yubikeys.nix` holds real serials and age recipients; `kdn.hw.edid.modelines` is already neutral, `hw/edid/default.nix:13-23` |
| `locale` | 1 | 150 | 5 | `kdn.locale` | NO (in flux) | defaults are neutral now: `locale/default.nix:25,36,42` |
| `managed` | 1 | 158 | 3 | `kdn.managed` | NO | — |
| `monitoring` | 1 | 97 | 2 | `kdn.monitoring.prometheus-stack` | NO | — |
| `networking` | 8 | 2863 | 16 | `kdn.networking`, `kdn.networking.{dynamic-hosts,netbird,openfortivpn,openvpn,resolved,router,tailscale}` | NO | — |
| `nix` | 1 | 104 | **0** | `kdn.nix.remote-builder` | NO | — |
| `outputs` | 1 | 27 | 1 | `kdn.outputs.host` | NO | — |
| `packaging` | 1 | 52 | 4 | `kdn.packaging.asdf` | NO | — |
| `profile` | 16 | 2861 | 73 | `kdn.profile.{default-secrets,hardware,machine,remote-builders,user}` | **YES** | `kdn.profile.machine.basic` embeds a WiFi priority map at `profile/machine/basic/default.nix:92`; `profile/machine/baseline/ssh_known_hosts` is a 55-line fleet file, read at `profile/machine/baseline/default.nix:375`; `kdn.profile.user.<u>.ssh.authorizedKeysFile` and `.gpg.publicKeys` read sibling data files, `profile/user/kdn/default.nix:75-110` |
| `programs` | 40 | 2781 | 128 | 39 prefixes under `kdn.programs.*` | NO (in flux) | — |
| `security` | 6 | 605 | 15 | `kdn.security.{disk-encryption,secrets,secrets.age,secrets.sops,secure-boot}` | NO | — |
| `services` | 14 | 1206 | 38 | 11 prefixes under `kdn.services.*` | NO (in flux) | `kdn.services.printing.printers` and `kdn.services.samba.defaults.*` are neutral now, `services/printing/default.nix:33-35`, `services/samba/default.nix:14-43` |
| `toolset` | 12 | 605 | 34 | 11 prefixes under `kdn.toolset.*` | NO | — |
| `virtualisation` | 10 | 620 | 31 | `kdn.virtualisation.{containers,libvirtd,microvm,vagrant}` | NO | — |
| root files | 6 | 699 | — | `kdn.{enable,args,hostName,nixConfig,nixpkgs,nix}` at `_options.nix:7-18` | NO (in flux) | `_stylix.nix:47` uses a neutral nixpkgs wallpaper now |

Two size numbers in the 014 definition drift by one: `programs` measures 128 `kdnConfig`
references, not 129; `virtualisation` measures 31, not 32. Every other size number confirms.

Task 009's personal-value table is **partly stale**. A `data/` folder already exists and holds
`desktop-sway-kanshi.nix`, `development-nix.nix`, `hw-edid.nix`, `locale.nix`,
`programs-photoprism.nix`, `services-printing.nix`, `services-samba.nix` and `stylix.nix`. So
only two areas still carry a value inside the module tree: `hw` and `profile`.

## Table 2 — cross-area coupling, the important column

`READS` is the hard edge: the area evaluates another area's option, so that other area must
migrate first. `WRITES` is the soft edge: the area assigns another area's option, so the target
option only needs to exist.

| Area | READS other areas (`n/f`) | WRITES other areas (`n/f`) |
|---|---|---|
| `apps` | — | `disks`:12/1, `env`:1/1 |
| `desktop` | `locale`:1/1 | `env`:12/7, `programs`:4/3, `disks`:2/1 |
| `development` | `desktop`:3/3 | `env`:27/24, `disks`:8/4, `apps`:4/4, `toolset`:2/2, `packaging`:1/1 |
| `disks` | `fs`:1/1, `hostName`:3/1 | `fs`:3/2, `security`:1/1 |
| `emulation` | `desktop`:1/1 | `apps`:1/1 |
| `env` | **none** | **none** |
| `fs` | `hostName`:2/2 | `disks`:1/1, `env`:1/1 |
| `headless` | — | `toolset`:7/1, `programs`:4/1, `disks`:3/1, `development`:1/1, `hw`:1/1 |
| `helpers` | **none** | **none** |
| `hw` | `desktop`:3/3, `security`:2/1, `hostName`:1/1 | `env`:15/10, `security`:4/1, `disks`:3/2, `programs`:2/2, `toolset`:1/1 |
| `locale` | — | `env`:3/1 |
| `managed` | `security`:1/1 | — |
| `monitoring` | — | `env`:1/1 |
| `networking` | `security`:3/2, `hostName`:2/1 | `fs`:6/1, `disks`:6/3, `env`:5/5, `managed`:3/2, `services`:2/1 |
| `nix` | **none** | **none** |
| `outputs` | `disks`:1/1 | — |
| `packaging` | — | `env`:1/1, `toolset`:1/1 |
| `profile` | `desktop`:24/3, `security`:11/4, `hostName`:5/3, `development`:3/1, `locale`:1/1, `managed`:1/1, `nix`:1/1, `programs`:1/1 | 17 areas; the largest are `programs`:45/7, `env`:24/11, `networking`:15/3, `hw`:13/8 |
| `programs` | `apps`:9/9, `desktop`:4/2, `security`:1/1 | `apps`:44/26, `env`:15/12, `disks`:8/6, `desktop`:4/2 |
| `security` | **none** | `env`:2/2, `toolset`:2/2 |
| `services` | `security`:4/1, `disks`:2/1, `hostName`:2/1 | `disks`:15/7, `env`:7/7, `networking`:3/2, `fs`:1/1 |
| `toolset` | `desktop`:2/2 | `env`:15/10, `programs`:5/4, `apps`:2/2, `services`:1/1 |
| `virtualisation` | `disks`:1/1, `hostName`:1/1 | `disks`:7/4, `env`:9/9, `hw`:1/1, `profile`:1/1, `programs`:1/1 |

Citations for the edges that change the batch order:

- `outputs/host/default.nix:15` reads `config.kdn.disks.luks.volumes`.
- `emulation/wine/default.nix:31` asserts `config.kdn.desktop.enable`.
- `managed/default.nix:150` guards on `config.kdn.security.secrets.allowed`.
- `disks/default.nix:128` asserts on `config.kdn.fs.disko.luks-zfs.enable`; `disks/default.nix:211`
  and `:392` build a name from `config.kdn.hostName`.
- `desktop/sway/home-manager/default.nix:259` reads `config.kdn.locale.xkbLayout`.
- `toolset/ide/default.nix:27` and `toolset/network/default.nix:37` read `config.kdn.desktop.enable`.
- `security/disk-encryption/default.nix:21`, `security/secure-boot/default.nix:21` and
  `packaging/asdf/default.nix:24` write `kdn.toolset.*.enable`.
- `headless/base/default.nix:61-74` writes 12 enables into 5 other areas.
- `programs/firefox/default.nix:12` reads `config.kdn.apps.firefox`; `:81` writes `kdn.apps.firefox`.
- `networking/tailscale/default.nix:12` and `networking/netbird/default.nix:86` read
  `config.kdn.security.secrets.sops.secrets.default.*`.
- `services/k8s/node/default.nix:71` reads `config.kdn.disks.zpool-main.name`.

`profile` sets **112** `*.enable` values outside its own prefix. That confirms the 014 note.

### One new coupling direction

`modules/universal/default.nix:226` writes `kdn.homebrew.enable`, and that option lives in
`modules/den/aspects/homebrew.nix`. So the loader now depends on the den tree. Both files are in
flux. Treat this as a fact to re-measure before batch 7.

## Table 3 — third-party flake-input module imports

Only 5 shared files import a third-party module. The rest of the tree imports none. The loader
holds most of them.

| Area / file | Imported modules | Conditional on |
|---|---|---|
| root `default.nix:28,44-57` (in flux) | `sops-nix` (3 targets), `home-manager` (2), `nix-homebrew`, `angrr` (2), `disko`, `lanzaboote`, `nur`, `preservation` | **class** — `moduleType` picks the branch |
| root `_stylix.nix:21-27` (in flux) | `stylix` for nixos, darwin, nix-on-droid, home | **class** — `moduleType` |
| `profile/hardware/rpi4/default.nix:34-40` | `argon40-nix`, `nixos-hardware.raspberry-pi-4`, two `nixpkgs` sd-image profiles | **DATA** — `kdnConfig.features.rpi4` and `features.installer`, lines 16-18 |
| `profile/hardware/darwin-utm-guest/default.nix:18` | a `nixpkgs` qemu-guest profile | **DATA** — `kdnConfig.features.darwin-utm-guest`, line 13 |
| `virtualisation/microvm/{host,guest}/default.nix:13,15-16` | `microvm.nixosModules.host`, `microvm.nixosModules.microvm-options` | **DATA** for the guest — `!kdnConfig.features.microvm-guest`, line 15 |

So the conditional-imports requirement of task 005 touches exactly **3 areas**: `profile`
(2 files) and `virtualisation` (1 file). The other 20 areas need no conditional import.

## Table 4 — guard sites, class versus non-class

| Area | Class dispatch | Non-class |
|---|---|---|
| `apps` | 3 | 1 |
| `desktop` | 16 | 6 |
| `development` | 45 | 0 |
| `disks` | 2 | 0 |
| `emulation` | 1 | 1 |
| `env` | 3 | 0 |
| `fs` | 3 | 0 |
| `headless` | 5 | 0 |
| `helpers` | 1 | 0 |
| `hw` | 18 | 0 |
| `locale` | 4 | 0 |
| `managed` | 2 | 0 |
| `monitoring` | 1 | 0 |
| `networking` | 8 | 0 |
| `nix` | **0** | **0** |
| `outputs` | **0** | **0** |
| `packaging` | 3 | 0 |
| `profile` | 38 | 4 |
| `programs` | 71 | 18 |
| `security` | 9 | 1 |
| `services` | 14 | 1 |
| `toolset` | 21 | 1 |
| `virtualisation` | 11 | 1 |
| root files | 11 | 3 |
| **total (shared tree)** | **290** | **37** |

The 014 definition reports 292 class sites. The two extra sites sit in the machine-local area,
which this audit excludes. The 37 non-class sites match the definition exactly: 30
`hasParentOfAnyType`, 5 loader, 2 `hasSops`.

`nix` and `outputs` need no guard at all. `nix` takes no `kdnConfig` argument either.

## Answer 1 — the zero-coupling areas

Three areas have **zero** cross-area coupling in both directions:

| Area | Files | Lines | `kdnConfig` | Guards |
|---|---|---|---|---|
| `nix` | 1 | 104 | 0 | 0 |
| `helpers` | 1 | 79 | 2 | 1 class |
| `env` | 1 | 73 | 4 | 3 class |

`nix` is the true pilot: no coupling, no `kdnConfig`, no guard.

Nine more areas have zero **read** coupling, so they carry only soft edges: `apps`, `headless`,
`locale`, `monitoring`, `packaging`, `security`, plus the three above.

## Answer 2 — the `env` coupling, both directions

`env` couples **outward to nothing**. It reads no other area's option and it writes none.
All 6 reads of `kdn.env.*` sit inside the declaring file, at `env/default.nix:61,62,65,66,69,70`.

`env` is a pure sink. 149 references across 105 files write into it. 143 of those 149 are writes.

| Area | Files that write `kdn.env.*` |
|---|---|
| `development` | 24 |
| `programs` | 12 |
| `profile` | 11 |
| `hw` | 10 |
| `toolset` | 10 |
| `virtualisation` | 9 |
| `desktop` | 7 |
| `services` | 7 |
| `networking` | 5 |
| `security` | 2 |
| `apps` | 1 |
| `fs` | 1 |
| `locale` | 1 |
| `monitoring` | 1 |
| `packaging` | 1 |
| `env` itself | 1 |
| one machine-local area | 2 |
| root files | **0** |
| **total** | **105** |

15 shared areas write into `env`. 7 shared areas do not: `disks`, `emulation`, `headless`,
`helpers`, `managed`, `nix` and `outputs`. The 6 root files write none either.

**So the 014 definition is wrong to call `env` a batch-2 item.** `env` has no dependency of its
own, and 102 other files depend on it. It belongs in batch 1, with `nix` and `helpers`.

## Answer 3 — the 37 non-class guard sites, file and line

### `hasParentOfAnyType` — 30 sites

Two personal user directories are masked as `<user-b>` and `<user-c>`.

| File | Line |
|---|---|
| `_stylix.nix` (in flux) | 89 |
| `emulation/wine/default.nix` | 20 |
| `toolset/print-3d/default.nix` | 21 |
| `desktop/sway/home-manager/default.nix` | 29 |
| `desktop/sway/home-manager/nwg-shell/default.nix` | 79 |
| `desktop/sway/home-manager/nwg-shell/nwg-panel/default.nix` | 53 |
| `desktop/sway/home-manager/swaync/default.nix` | 9 |
| `desktop/sway/home-manager/kanshi/default.nix` | 154 |
| `desktop/base/default.nix` | 50 |
| `programs/beeper/default.nix` | 21 |
| `programs/nextcloud-client/default.nix` | 21 |
| `programs/ssh-client/default.nix` | 52 (`darwin`, not `nixos`) |
| `programs/spotify/default.nix` | 21 |
| `programs/element/default.nix` | 41 |
| `programs/wofi/default.nix` | 20 |
| `programs/rambox/default.nix` | 21 |
| `programs/slack/default.nix` | 21 |
| `programs/blender/default.nix` | 20 |
| `programs/signal/default.nix` | 21 |
| `programs/orca-slicer/default.nix` | 20 |
| `programs/weechat/default.nix` | 90 |
| `programs/ente-photos/default.nix` | 23 |
| `programs/tidal/default.nix` | 21 |
| `programs/keepassxc/default.nix` | 33 |
| `programs/kdeconnect/default.nix` | 45 (combined with `isOfType`) |
| `profile/user/kdn/default.nix` | 380 |
| `profile/user/<user-b>/default.nix` | 79 |
| `profile/user/<user-c>/default.nix` | 90 |
| `virtualisation/containers/default.nix` | 86 |
| `services/syncthing/default.nix` | 26 |

28 of the 30 test `[ "nixos" ]`. One tests `[ "darwin" ]`. One combines the test with `isOfType`.

### The loader — 5 sites

| File | Line | Call |
|---|---|---|
| `default.nix` (in flux) | 32 | `util.loadModules` — the Home Manager shared-module injection |
| `default.nix` (in flux) | 59 | `util.loadModules` — the top-level recursive load |
| `apps/default.nix` | 107 | `util.modules.forwardAttrsAsDefaults` |
| `programs/handlr/default.nix` | 45 | `util.modules.forwardAttrsAsDefaults` |
| `programs/fish/default.nix` | 28 | `util.modules.forwardAttrsAsDefaults` |

`util.modules.forwardAttrsAsDefaults` is not the loader. It is a separate helper with 3 sites, and
it forwards a whole `cfg` into `home-manager.sharedModules`. Treat it as its own design item.

### `hasSops` — 2 sites

| File | Line |
|---|---|
| `security/secrets/sops/default.nix` | 11 |
| `profile/remote-builders/default.nix` | 18 |

## Answer 4 — the corrected batch order

The 014 table sorts by file count and `kdnConfig` count. Real coupling gives a different order.
Six placements in that table are wrong.

### The six corrections

| Area | 014 batch | Correct batch | Reason, with a citation |
|---|---|---|---|
| root `_options.nix` + `nix.nix` | 6 — last | **1 — first** | 7 areas read `config.kdn.hostName`. `disks/default.nix:211`, `fs`, `hw`, `networking`, `profile`, `services`, `virtualisation`. The loader stays last; the option file cannot. |
| `env` | 2 | **1** | Zero outward coupling, 102 dependent files. See Answer 2. |
| `outputs` | 1 | **after `disks`** | `outputs/host/default.nix:15` reads `config.kdn.disks.luks.volumes`. |
| `emulation` | 1 | **after `desktop`** | `emulation/wine/default.nix:31` asserts `config.kdn.desktop.enable`. |
| `managed` | 1 | **after `security`** | `managed/default.nix:150` guards on `config.kdn.security.secrets.allowed`. |
| `disks` | 2 | **after `fs`** | `disks/default.nix:128` asserts on `config.kdn.fs.disko.luks-zfs.enable`. The 014 table puts `fs` in batch 3, one batch late. |
| `headless` | 2 | **5 — much later** | `headless/base/default.nix:61-74` writes 12 enables into `development`, `hw`, `programs`, `toolset` and `disks`. All four are batch 4 or 5. |

### The corrected order

| Batch | Areas | Why |
|---|---|---|
| **1 — pilot** | root `_options.nix`, root `nix.nix`, `nix`, `helpers`, `env` | Zero read coupling. `kdn.hostName` and `kdn.env.*` unlock everything after. 5 files, about 460 lines, 6 `kdnConfig` references, 4 class guards, 0 non-class guards. |
| **2 — sinks** | `apps`, `locale`, `monitoring`, `packaging`, `security` | No read of another area. Each writes only into a batch-1 option, or into `toolset`. |
| **3** | `fs`, `desktop`, `networking`, `managed` | One hard edge each, into batch 1 or 2. `desktop` reads `locale`; `networking` and `managed` read `security`; `fs` reads `hostName`. |
| **4** | `disks`, `toolset`, `hw`, `development`, `emulation` | Each reads a batch-3 area. `disks` reads `fs`; the other four read `desktop`. |
| **5** | `outputs`, `virtualisation`, `services`, `programs`, `headless` | Each reads or writes a batch-4 area. `headless` moves here from batch 2. |
| **6 — hardest** | `profile` | 8 read edges over 7 areas, 112 cross-area enable writes, and both task-009 blockers. |
| **7 — the loader, last** | `default.nix`, `_hm-bootstrap.nix`, `_stylix.nix`, `ascii-workaround.nix` | The recursive load and the Home Manager injection. Every earlier batch needs it. |

### Two soft edges the order cannot remove

`security/disk-encryption/default.nix:21`, `security/secure-boot/default.nix:21` and
`packaging/asdf/default.nix:24` write `kdn.toolset.*.enable`. `security` and `packaging` sit in
batch 2; `toolset` sits in batch 4, because it reads `desktop`. So the order holds a forward
reference. Two ways out, and the choice belongs to the owner:

1. Declare `kdn.toolset.*.enable` in batch 2 as a stub, and fill it in batch 4.
2. Move those three writes into the consuming host config, and out of the module.

`headless/base/default.nix:61-74` holds the same shape at a larger scale. Batch 5 removes it.

### The one thing this order does not change

`profile` stays last among the areas, and the loader stays after it. The 014 definition is right
on both.

## Follow-up notes

- Re-measure the `modules/universal/default.nix` → `modules/den/aspects/homebrew.nix` edge after
  the current edits land. A universal-to-den write is a new direction.
- Task 009's personal-value table needs an update. The `data/` folder already holds 8 files, and
  `locale`, `services/printing`, `services/samba`, `hw/edid`, `_stylix` and `development/nix` are
  neutral now. Only `hw/yubikey/yubikeys.nix` and 3 files under `profile/` still carry a value.
- `util.modules.forwardAttrsAsDefaults` has 3 sites and needs a design answer of its own. Step 3
  of task 014 groups it with the loader, and the two are not the same mechanism.
