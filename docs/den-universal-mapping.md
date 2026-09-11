---
type: Reference
description: Maps every modules/universal module to its modules/den/aspects counterpart, with a port status per module and the gaps that remain.
timestamp: 2026-09-11T20:20:00+02:00
authored_by: agent
---

# `modules/universal` → `modules/den/aspects` mapping

`modules/universal/` is the deprecated tree. `modules/den/aspects/` is the replacement. The port
runs in batches, so both trees hold the same concern at the same time. This file answers one
question per old module: **does a den aspect serve it yet, and under which name?**

Use it for three jobs:

1. Find the aspect that replaces an old module.
2. Find the old modules that still have no aspect, so you can plan the next batch.
3. Find the den aspects that no old module backs, so you know what is genuinely new.

## The state this file describes

The counts come from one commit stack state. Check that state before you trust a number.

| Item | Value |
|---|---|
| Last den change id | `pusnvyssmyol` (commit `40cb5f02`) |
| Its description | `fix(den): guard the k8s zfs write and repair two probes` |
| Measured | 2026-09-11 |

Every aspect file has a registry entry, and every registry entry points at a file that exists. No
batch waits for a name. `.cache/agent-notes/sub-agent-outputs/mapping-doc-refresh/refresh.sh`
re-derives every number below; `## How to refresh this doc` names the command per count.

Two trees carry a private subtree. Every count below excludes it.

## Summary

| Status | Old modules | Meaning |
|---|---|---|
| `ported` | 167 | An aspect exists and `modules/den/lib.nix` registers it. |
| `not ported` | 5 | No aspect names it yet. |
| `shared` | 1 | No aspect, but a file under `modules/den/common/` serves the concern. |
| `excluded` | 3 | A deliberate decision keeps it out of den. |
| **Total** | **176** | Every `modules/universal/**/default.nix`, private subtree excluded. |

`refresh.sh measure` prints the four counts, and `refresh.sh fix` derives the `Status` cell of every
row from the registry. So the column cannot drift from the registry; only a `shared` or an
`excluded` decision is human.

Registry side, measured on the same stack:

| Item | Value |
|---|---|
| Names in the `aspectModules` set of `modules/den/lib.nix` | 205 |
| Distinct targets those names point at | 174 |
| Targets that are a `.nix` file | 172 |
| Targets that are a directory with a `default.nix` | 2 |
| Top-level `.nix` files in `modules/den/aspects/` | 172 |
| Unregistered top-level `.nix` files | 0 |
| Registry targets that do not exist | 0 |

The registry is a **many-to-one** map, so a `readDir` scan of `modules/den/aspects/` gives the wrong
name count. Parse the attribute set instead. Ten files serve more than one name:

| File | Names it serves |
|---|---|
| `aspects/toolset.nix` | 11 |
| `aspects/service-k8s.nix` | 5 |
| `aspects/net-router.nix` | 5 |
| `aspects/profile-headless.nix` | 4 |
| `aspects/desktop-sway-small.nix` | 4 |
| `aspects/profile-baseline.nix` | 3 |
| `aspects/fs.nix` | 3 |
| `aspects/stylix.nix` | 2 |
| `aspects/desktop-sway.nix` | 2 |
| `aspects/desktop-sway-nwg.nix` | 2 |

A directory target holds a `default.nix` plus its data files. Two targets have that shape today:
`aspects/program-gnupg` and `aspects/program-zsh`.

A name of a multi-name file rarely matches the file base name, so that difference carries no
information. Four **sole-name** files still differ from the name they serve:

| Registry name | File |
|---|---|
| `emulation-wine` | `aspects/emulation.nix` |
| `monitoring-prometheus-stack` | `aspects/monitoring.nix` |
| `outputs-host` | `aspects/outputs.nix` |
| `packaging-asdf` | `aspects/packaging.nix` |

## The main table

One row per `modules/universal/**/default.nix`. The `kdn.*` prefix column names the option root the
old module **declares** — not the file name. Match on that prefix, because the names often differ.
A `—` in the prefix column means the module declares no option; it only writes a sibling's option.

### (root)

| old module | `kdn.*` prefix | den aspect | Status |
|---|---|---|---|
| `modules/universal/default.nix` | `kdn` (in `_options.nix`) | `homebrew`, `homebrew-nix-managed` | `excluded` |

### apps

| old module | `kdn.*` prefix | den aspect | Status |
|---|---|---|---|
| `modules/universal/apps/default.nix` | `kdn.apps` | `apps` | `ported` |

### desktop

| old module | `kdn.*` prefix | den aspect | Status |
|---|---|---|---|
| `modules/universal/desktop/base/default.nix` | `kdn.desktop.base` | `desktop-base` | `ported` |
| `modules/universal/desktop/default.nix` | `kdn.desktop` | — | `shared` |
| `modules/universal/desktop/kde/default.nix` | `kdn.desktop.kde` | `desktop-kde` | `ported` |
| `modules/universal/desktop/remote-server/default.nix` | `kdn.desktop.remote-server` | `desktop-remote-server` | `ported` |
| `modules/universal/desktop/sway/default.nix` | `kdn.desktop.sway` | `desktop-sway` | `ported` |
| `modules/universal/desktop/sway/home-manager/default.nix` | `kdn.desktop.sway` | `desktop-sway` | `ported` |
| `modules/universal/desktop/sway/home-manager/kanshi/default.nix` | `kdn.desktop.sway.kanshi` | `desktop-sway-kanshi` | `ported` |
| `modules/universal/desktop/sway/home-manager/nwg-shell/default.nix` | `services.nwg-shell` | `desktop-sway-nwg-shell` | `ported` |
| `modules/universal/desktop/sway/home-manager/nwg-shell/nwg-panel/default.nix` | `services.nwg-shell.panel` | `desktop-sway-nwg-panel` | `ported` |
| `modules/universal/desktop/sway/home-manager/swaync/default.nix` | — | `desktop-sway-swaync` | `ported` |
| `modules/universal/desktop/sway/remote/default.nix` | `kdn.desktop.sway.remote` | `desktop-sway-remote` | `ported` |

One row of this area carries no aspect. `desktop/default.nix` is `shared`:
`modules/den/common/graphical.nix` declares `kdn.graphical`, and each desktop aspect reads it, so the
flag needs no aspect of its own. A `not ported` cell would ask for a port that the design rejects.

Four more aspects come from this area and get no row, because each ports a file that is not a
`default.nix`. `## Reverse: den aspects that no old module backs` lists all four.

### development

| old module | `kdn.*` prefix | den aspect | Status |
|---|---|---|---|
| `modules/universal/development/android/default.nix` | `kdn.development.android` | `dev-android` | `ported` |
| `modules/universal/development/ansible/default.nix` | `kdn.development.ansible` | `dev-ansible` | `ported` |
| `modules/universal/development/cloud/aws/default.nix` | `kdn.development.cloud.aws` | `dev-cloud-aws` | `ported` |
| `modules/universal/development/cloud/azure/default.nix` | `kdn.development.cloud.azure` | `dev-cloud-azure` | `ported` |
| `modules/universal/development/cloud/default.nix` | `kdn.development.cloud` | `dev-cloud` | `ported` |
| `modules/universal/development/data/default.nix` | `kdn.development.data` | `dev-data` | `ported` |
| `modules/universal/development/db/default.nix` | `kdn.development.db` | `dev-db` | `ported` |
| `modules/universal/development/documents/default.nix` | `kdn.development.documents` | `dev-documents` | `ported` |
| `modules/universal/development/dotnet/default.nix` | `kdn.development.dotnet` | `dev-dotnet` | `ported` |
| `modules/universal/development/elixir/default.nix` | `kdn.development.elixir` | `dev-elixir` | `ported` |
| `modules/universal/development/git/default.nix` | `kdn.development.git` | `dev-git` | `ported` |
| `modules/universal/development/golang/default.nix` | `kdn.development.golang` | `dev-golang` | `ported` |
| `modules/universal/development/java/default.nix` | `kdn.development.java` | `dev-java` | `ported` |
| `modules/universal/development/jetbrains/default.nix` | `kdn.development.jetbrains` | `dev-jetbrains` | `ported` |
| `modules/universal/development/k8s/default.nix` | `kdn.development.k8s` | `dev-k8s` | `ported` |
| `modules/universal/development/kernel/default.nix` | `kdn.development.kernel` | `dev-kernel` | `ported` |
| `modules/universal/development/llm/claude-code/default.nix` | `kdn.development.llm.claude-code` | `dev-llm-claude-code` | `ported` |
| `modules/universal/development/llm/omp/default.nix` | `kdn.development.llm.omp` | `dev-llm-omp` | `ported` |
| `modules/universal/development/llm/opencode/default.nix` | `kdn.development.llm.opencode` | `dev-llm-opencode` | `ported` |
| `modules/universal/development/llm/pi/default.nix` | `kdn.development.llm.pi` | `dev-llm-pi` | `ported` |
| `modules/universal/development/lua/default.nix` | `kdn.development.lua` | `dev-lua` | `ported` |
| `modules/universal/development/nickel/default.nix` | `kdn.development.nickel` | `dev-nickel` | `ported` |
| `modules/universal/development/nix/default.nix` | `kdn.development.nix` | `dev-nix` | `ported` |
| `modules/universal/development/nodejs/default.nix` | `kdn.development.nodejs` | `dev-nodejs` | `ported` |
| `modules/universal/development/python/default.nix` | `kdn.development.python` | `dev-python` | `ported` |
| `modules/universal/development/rpi/default.nix` | `kdn.development.rpi` | `dev-rpi` | `ported` |
| `modules/universal/development/rust/default.nix` | `kdn.development.rust` | `dev-rust` | `ported` |
| `modules/universal/development/shell/default.nix` | `kdn.development.shell` | `dev-shell` | `ported` |
| `modules/universal/development/terraform/default.nix` | `kdn.development.terraform` | `dev-terraform` | `ported` |
| `modules/universal/development/web/default.nix` | `kdn.development.web` | `dev-web` | `ported` |

### disks

| old module | `kdn.*` prefix | den aspect | Status |
|---|---|---|---|
| `modules/universal/disks/default.nix` | `kdn.disks` | `disks`, `disks-persist` | `ported` |

### emulation

| old module | `kdn.*` prefix | den aspect | Status |
|---|---|---|---|
| `modules/universal/emulation/wine/default.nix` | `kdn.emulation.wine` | `emulation-wine` | `ported` |

### env

| old module | `kdn.*` prefix | den aspect | Status |
|---|---|---|---|
| `modules/universal/env/default.nix` | `kdn.env.packages` | — | `excluded` |

### fs

| old module | `kdn.*` prefix | den aspect | Status |
|---|---|---|---|
| `modules/universal/fs/disko/luks-zfs/default.nix` | `kdn.fs.disko.luks-zfs` | `fs-luks-zfs` | `ported` |
| `modules/universal/fs/watch/default.nix` | `kdn.fs.watch` | `fs-watch` | `ported` |
| `modules/universal/fs/zfs/default.nix` | `kdn.fs.zfs` | `fs-zfs` | `ported` |

### headless

| old module | `kdn.*` prefix | den aspect | Status |
|---|---|---|---|
| `modules/universal/headless/base/default.nix` | `kdn.headless.base` | `profile-headless` | `ported` |

### helpers

| old module | `kdn.*` prefix | den aspect | Status |
|---|---|---|---|
| `modules/universal/helpers/default.nix` | `kdn.helpers` | — | `excluded` |

### hw

| old module | `kdn.*` prefix | den aspect | Status |
|---|---|---|---|
| `modules/universal/hw/audio/default.nix` | `kdn.hw.audio` | `hw-audio` | `ported` |
| `modules/universal/hw/basic/default.nix` | `kdn.hw.basic` | `hw-basic` | `ported` |
| `modules/universal/hw/bluetooth/default.nix` | `kdn.hw.bluetooth` | `hw-bluetooth` | `ported` |
| `modules/universal/hw/cpu/amd/default.nix` | `kdn.hw.cpu.amd` | `hw-cpu-amd` | `ported` |
| `modules/universal/hw/cpu/intel/default.nix` | `kdn.hw.cpu.intel` | `hw-cpu-intel` | `ported` |
| `modules/universal/hw/edid/default.nix` | `kdn.hw.edid` | `hw-edid` | `ported` |
| `modules/universal/hw/gpu/amd/default.nix` | `kdn.hw.gpu.amd` | `hw-gpu-amd` | `ported` |
| `modules/universal/hw/gpu/default.nix` | `kdn.hw.gpu` | `hw-gpu` | `ported` |
| `modules/universal/hw/gpu/intel/default.nix` | `kdn.hw.gpu.intel` | `hw-gpu-intel` | `ported` |
| `modules/universal/hw/intel-graphics-fix/default.nix` | `kdn.hw.intel-graphics-fix` | `hw-intel-graphics-fix` | `ported` |
| `modules/universal/hw/modem/default.nix` | `kdn.hw.modem` | `hw-modem` | `ported` |
| `modules/universal/hw/nanokvm/default.nix` | `kdn.hw.nanokvm` | `hw-nanokvm` | `ported` |
| `modules/universal/hw/qmk/default.nix` | `kdn.hw.qmk` | `hw-qmk` | `ported` |
| `modules/universal/hw/usbip/default.nix` | `kdn.hw.usbip` | `hw-usbip` | `ported` |
| `modules/universal/hw/yubikey/default.nix` | `kdn.hw.yubikey` | `hw-yubikey` | `ported` |

### locale

| old module | `kdn.*` prefix | den aspect | Status |
|---|---|---|---|
| `modules/universal/locale/default.nix` | `kdn.locale` | `locale` | `ported` |

### managed

| old module | `kdn.*` prefix | den aspect | Status |
|---|---|---|---|
| `modules/universal/managed/default.nix` | `kdn.managed` | `managed` | `ported` |

### monitoring

| old module | `kdn.*` prefix | den aspect | Status |
|---|---|---|---|
| `modules/universal/monitoring/prometheus-stack/default.nix` | `kdn.monitoring.prometheus-stack` | `monitoring-prometheus-stack` | `ported` |

### networking

| old module | `kdn.*` prefix | den aspect | Status |
|---|---|---|---|
| `modules/universal/networking/default.nix` | `kdn.networking` | `net-interfaces` | `ported` |
| `modules/universal/networking/dynamic-hosts/default.nix` | `kdn.networking.dynamic-hosts` | `net-dynamic-hosts` | `ported` |
| `modules/universal/networking/netbird/default.nix` | `kdn.networking.netbird` | `net-netbird` | `ported` |
| `modules/universal/networking/openfortivpn/default.nix` | `kdn.networking.openfortivpn` | `net-openfortivpn` | `ported` |
| `modules/universal/networking/openvpn/default.nix` | `kdn.networking.openvpn` | `net-openvpn` | `ported` |
| `modules/universal/networking/resolved/default.nix` | `kdn.networking.resolved` | `net-resolved` | `ported` |
| `modules/universal/networking/router/default.nix` | `kdn.networking.router` | `net-router` | `ported` |
| `modules/universal/networking/tailscale/default.nix` | `kdn.networking.tailscale` | `net-tailscale` | `ported` |

### nix

| old module | `kdn.*` prefix | den aspect | Status |
|---|---|---|---|
| `modules/universal/nix/remote-builder/default.nix` | `kdn.nix.remote-builder` | `nix-remote-builder` | `ported` |

### outputs

| old module | `kdn.*` prefix | den aspect | Status |
|---|---|---|---|
| `modules/universal/outputs/host/default.nix` | `kdn.outputs.host` | `outputs-host` | `ported` |

### packaging

| old module | `kdn.*` prefix | den aspect | Status |
|---|---|---|---|
| `modules/universal/packaging/asdf/default.nix` | `kdn.packaging.asdf` | `packaging-asdf` | `ported` |

### profile

| old module | `kdn.*` prefix | den aspect | Status |
|---|---|---|---|
| `modules/universal/profile/default-secrets/default.nix` | `kdn.profile.default-secrets` | — | `not ported` |
| `modules/universal/profile/hardware/darwin-utm-guest/default.nix` | `kdn.profile.hardware.darwin-utm-guest` | `hw-darwin-utm-guest` | `ported` |
| `modules/universal/profile/hardware/dell-e5470/default.nix` | `kdn.profile.hardware.dell-e5470` | `hw-dell-e5470` | `ported` |
| `modules/universal/profile/hardware/rpi4/default.nix` | `kdn.profile.hardware.rpi4` | — | `not ported` |
| `modules/universal/profile/machine/baseline/default.nix` | `kdn.profile.machine.baseline` | `profile-baseline` | `ported` |
| `modules/universal/profile/machine/basic/default.nix` | `kdn.profile.machine.basic` | `profile-basic` | `ported` |
| `modules/universal/profile/machine/desktop/default.nix` | `kdn.profile.machine.desktop` | `profile-desktop` | `ported` |
| `modules/universal/profile/machine/dev/default.nix` | `kdn.profile.machine.dev` | `profile-dev` | `ported` |
| `modules/universal/profile/machine/gaming/default.nix` | `kdn.profile.machine.gaming` | `profile-gaming` | `ported` |
| `modules/universal/profile/machine/hetzner/default.nix` | `kdn.profile.machine.hetzner` | `profile-hetzner` | `ported` |
| `modules/universal/profile/machine/workstation/default.nix` | `kdn.profile.machine.workstation` | `profile-workstation` | `ported` |
| `modules/universal/profile/remote-builders/default.nix` | `kdn.profile.remote-builders` | — | `not ported` |
| `modules/universal/profile/user/bn/default.nix` | `kdn.profile.user.bn` | `user` | `ported` |
| `modules/universal/profile/user/kdn/default.nix` | `kdn.profile.user.kdn` | `user` | `ported` |
| `modules/universal/profile/user/sn/default.nix` | `kdn.profile.user.sn` | `user` | `ported` |

### programs

| old module | `kdn.*` prefix | den aspect | Status |
|---|---|---|---|
| `modules/universal/programs/atuin/default.nix` | `kdn.programs.atuin` | `program-atuin` | `ported` |
| `modules/universal/programs/beeper/default.nix` | `kdn.programs.beeper` | `program-beeper` | `ported` |
| `modules/universal/programs/blender/default.nix` | `kdn.programs.blender` | `program-blender` | `ported` |
| `modules/universal/programs/browsers-launcher/default.nix` | `kdn.programs.browsers-launcher` | `program-browsers-launcher` | `ported` |
| `modules/universal/programs/chrome/default.nix` | `kdn.programs.chrome` | `program-chrome` | `ported` |
| `modules/universal/programs/chromium/default.nix` | `kdn.programs.chromium` | `program-chromium` | `ported` |
| `modules/universal/programs/dconf/default.nix` | `kdn.programs.dconf` | `program-dconf` | `ported` |
| `modules/universal/programs/direnv/default.nix` | `kdn.programs.direnv` | `program-direnv` | `ported` |
| `modules/universal/programs/editors/photo/default.nix` | `kdn.programs.editors.photo` | `program-editors-photo` | `ported` |
| `modules/universal/programs/editors/video/default.nix` | `kdn.programs.editors.video` | `program-editors-video` | `ported` |
| `modules/universal/programs/element/default.nix` | `kdn.programs.matrix` | `program-matrix` | `ported` |
| `modules/universal/programs/ente-photos/default.nix` | `kdn.programs.ente-photos` | `program-ente-photos` | `ported` |
| `modules/universal/programs/firefox/default.nix` | `kdn.programs.firefox` | `program-firefox` | `ported` |
| `modules/universal/programs/fish/default.nix` | `kdn.programs.fish` | `program-fish` | `ported` |
| `modules/universal/programs/gnupg/default.nix` | `kdn.programs.gnupg` | `program-gnupg` | `ported` |
| `modules/universal/programs/handlr/default.nix` | `kdn.programs.handlr` | `program-handlr` | `ported` |
| `modules/universal/programs/kdeconnect/default.nix` | `kdn.programs.kdeconnect` | `program-kdeconnect` | `ported` |
| `modules/universal/programs/keepass/default.nix` | `kdn.programs.keepass` | `program-keepass` | `ported` |
| `modules/universal/programs/keepassxc/default.nix` | `kdn.programs.keepassxc` | `program-keepassxc` | `ported` |
| `modules/universal/programs/logseq/default.nix` | `kdn.programs.logseq` | `program-logseq` | `ported` |
| `modules/universal/programs/midnight-commander/default.nix` | `kdn.programs.midnight-commander` | `program-midnight-commander` | `ported` |
| `modules/universal/programs/nextcloud-client/default.nix` | `kdn.programs.nextcloud-client` | `program-nextcloud-client` | `ported` |
| `modules/universal/programs/nix-index/default.nix` | `kdn.programs.nix-index` | `program-nix-index` | `ported` |
| `modules/universal/programs/obs-studio/default.nix` | `kdn.programs.obs-studio` | `program-obs-studio` | `ported` |
| `modules/universal/programs/office/default.nix` | `kdn.programs.office` | `program-office` | `ported` |
| `modules/universal/programs/orca-slicer/default.nix` | `kdn.programs.orca-slicer` | `program-orca-slicer` | `ported` |
| `modules/universal/programs/photoprism/default.nix` | `kdn.programs.photoprism` | `program-photoprism` | `ported` |
| `modules/universal/programs/rambox/default.nix` | `kdn.programs.rambox` | `program-rambox` | `ported` |
| `modules/universal/programs/signal/default.nix` | `kdn.programs.signal` | `program-signal` | `ported` |
| `modules/universal/programs/slack/default.nix` | `kdn.programs.slack` | `program-slack` | `ported` |
| `modules/universal/programs/spotify/default.nix` | `kdn.programs.spotify` | `program-spotify` | `ported` |
| `modules/universal/programs/ssh-client/default.nix` | `kdn.programs.ssh-client` | `program-ssh-client` | `ported` |
| `modules/universal/programs/terminal-ide/default.nix` | `kdn.programs.terminal-ide` | `program-terminal-ide` | `ported` |
| `modules/universal/programs/thunderbird/default.nix` | `kdn.programs.thunderbird` | `program-thunderbird` | `ported` |
| `modules/universal/programs/tidal/default.nix` | `kdn.programs.tidal` | `program-tidal` | `ported` |
| `modules/universal/programs/torrent/default.nix` | `kdn.programs.torrent` | `program-torrent` | `ported` |
| `modules/universal/programs/weechat/default.nix` | `kdn.programs.weechat` | `program-weechat` | `ported` |
| `modules/universal/programs/wofi/default.nix` | `kdn.programs.wofi` | `program-wofi` | `ported` |
| `modules/universal/programs/ydotool/default.nix` | `kdn.programs.ydotool` | `program-ydotool` | `ported` |
| `modules/universal/programs/zsh/default.nix` | `kdn.programs.zsh` | `program-zsh` | `ported` |

### security

| old module | `kdn.*` prefix | den aspect | Status |
|---|---|---|---|
| `modules/universal/security/disk-encryption/default.nix` | `kdn.security.disk-encryption` | `security-disk-encryption` | `ported` |
| `modules/universal/security/secrets/age/default.nix` | `kdn.security.secrets.age` | `security-secrets-age` | `ported` |
| `modules/universal/security/secrets/default.nix` | `kdn.security.secrets` | `secrets` | `ported` |
| `modules/universal/security/secrets/sops/default.nix` | `kdn.security.secrets.sops` | `security-secrets-sops` | `ported` |
| `modules/universal/security/secure-boot/default.nix` | `kdn.security.secure-boot` | `security-secure-boot` | `ported` |

### services

| old module | `kdn.*` prefix | den aspect | Status |
|---|---|---|---|
| `modules/universal/services/caddy/default.nix` | `kdn.services.caddy` | `service-caddy` | `ported` |
| `modules/universal/services/coredns/default.nix` | `kdn.services.coredns` | `service-coredns` | `ported` |
| `modules/universal/services/home-assistant/default.nix` | `kdn.services.home-assistant` | `service-home-assistant` | `ported` |
| `modules/universal/services/iperf3/default.nix` | `kdn.services.iperf3` | `service-iperf3` | `ported` |
| `modules/universal/services/k8s/controlplane/loadbalancer/default.nix` | — | `service-k8s-controlplane-lb` | `ported` |
| `modules/universal/services/k8s/default.nix` | `kdn.services.k8s` | `service-k8s` | `ported` |
| `modules/universal/services/k8s/kubeadm/default.nix` | `kdn.services.k8s.kubeadm` | `service-k8s-kubeadm` | `ported` |
| `modules/universal/services/k8s/node/default.nix` | `kdn.services.k8s.node` | `service-k8s-node` | `ported` |
| `modules/universal/services/nextcloud-client-nixos/default.nix` | `kdn.services.nextcloud-client-nixos` | `service-nextcloud-client` | `ported` |
| `modules/universal/services/postgresql/default.nix` | `kdn.services.postgresql` | `service-postgresql` | `ported` |
| `modules/universal/services/printing/default.nix` | `kdn.services.printing` | `service-printing` | `ported` |
| `modules/universal/services/samba/default.nix` | `kdn.services.samba` | `service-samba` | `ported` |
| `modules/universal/services/syncthing/default.nix` | `kdn.services.syncthing` | `service-syncthing` | `ported` |
| `modules/universal/services/zammad/default.nix` | `kdn.services.zammad` | `service-zammad` | `ported` |

### toolset

| old module | `kdn.*` prefix | den aspect | Status |
|---|---|---|---|
| `modules/universal/toolset/diagrams/default.nix` | `kdn.toolset.diagrams` | `toolset-diagrams` | `ported` |
| `modules/universal/toolset/essentials/default.nix` | `kdn.toolset.essentials` | `toolset-essentials` | `ported` |
| `modules/universal/toolset/fs/default.nix` | `kdn.toolset.fs` | `toolset-fs` | `ported` |
| `modules/universal/toolset/fs/encryption/default.nix` | `kdn.toolset.fs.encryption` | `toolset-fs-encryption` | `ported` |
| `modules/universal/toolset/ide/default.nix` | `kdn.toolset.ide` | — | `not ported` |
| `modules/universal/toolset/logs-processing/default.nix` | `kdn.toolset.logs-processing` | `toolset-logs-processing` | `ported` |
| `modules/universal/toolset/mikrotik/default.nix` | `kdn.toolset.mikrotik` | `toolset-mikrotik` | `ported` |
| `modules/universal/toolset/network/default.nix` | `kdn.toolset.network` | `toolset-network`, `toolset-network-gui` | `ported` |
| `modules/universal/toolset/nix/default.nix` | `kdn.toolset.nix` | `toolset-nix` | `ported` |
| `modules/universal/toolset/print-3d/default.nix` | `kdn.toolset.print-3d` | — | `not ported` |
| `modules/universal/toolset/tracing/default.nix` | `kdn.toolset.tracing` | `toolset-tracing` | `ported` |
| `modules/universal/toolset/unix/default.nix` | `kdn.toolset.unix` | `toolset-unix` | `ported` |

### virtualisation

| old module | `kdn.*` prefix | den aspect | Status |
|---|---|---|---|
| `modules/universal/virtualisation/containers/dagger/default.nix` | `kdn.virtualisation.containers.dagger` | `virt-containers-dagger` | `ported` |
| `modules/universal/virtualisation/containers/default.nix` | `kdn.virtualisation.containers` | `virt-containers` | `ported` |
| `modules/universal/virtualisation/containers/distrobox/default.nix` | `kdn.virtualisation.containers.distrobox` | `virt-containers-distrobox` | `ported` |
| `modules/universal/virtualisation/containers/docker/default.nix` | `kdn.virtualisation.containers.docker` | `virt-containers-docker` | `ported` |
| `modules/universal/virtualisation/containers/podman/default.nix` | `kdn.virtualisation.containers.podman` | `virt-containers-podman` | `ported` |
| `modules/universal/virtualisation/containers/x11docker/default.nix` | `kdn.virtualisation.containers.x11docker` | `virt-containers-x11docker` | `ported` |
| `modules/universal/virtualisation/libvirtd/default.nix` | `kdn.virtualisation.libvirtd` | `virt-libvirtd` | `ported` |
| `modules/universal/virtualisation/microvm/guest/default.nix` | `kdn.virtualisation.microvm.guest` | `virt-microvm-guest` | `ported` |
| `modules/universal/virtualisation/microvm/host/default.nix` | `kdn.virtualisation.microvm.host` | `virt-microvm-host` | `ported` |
| `modules/universal/virtualisation/vagrant/default.nix` | `kdn.virtualisation.vagrant` | `virt-vagrant` | `ported` |

## The deliberate exclusions

| Old module | Reason |
|---|---|
| `modules/universal/default.nix` | It is the auto-loader plus the tree-wide opinions. den needs no loader. Two parts of it **do** reach den: the Homebrew concern becomes `homebrew` and `homebrew-nix-managed`, and `_options.nix` plus `nix.nix` become `nix-config`. |
| `modules/universal/helpers/default.nix` | `kdn.helpers` is a script bag of this repository. An adopter wants none of it. |
| `modules/universal/env/default.nix` | den ships no `kdn.env.*` by design. Design B makes each target write the native option, and the old `apply` filter moves to `modules/den/common/filter-packages.nix`. |

`modules/universal/profile/remote-builders/default.nix` left this table.
`modules/den/aspects/nix-remote-builder.nix` states that a later batch ports it, so the module is
`not ported`, not excluded. The cross-host read stays the hard part of that port.

## Reverse: den aspects that no old module backs

41 registry names have no main-table row of their own. 19 come from `modules/slots/`, and 22 come
from a split or from a non-`default.nix` file. Cross-check: the main table names 168 distinct
aspects, the registry holds 205, and four split names also appear in a main-table cell —
`homebrew`, `homebrew-nix-managed`, `disks-persist` and `toolset-network-gui`. So
205 − 168 + 4 = 41.

### From `modules/slots/`

| Aspect | Source slot |
|---|---|
| `ca` | `modules/slots/ca/default.nix` |
| `devenv-cli` | `modules/slots/devenv/default.nix` |
| `gh` | `modules/slots/gh/default.nix` |
| `jj` | `modules/slots/jj/default.nix` |
| `jj-fork` | `modules/slots/jj/fork/default.nix` |
| `llm` | `modules/slots/llm/default.nix` |
| `llm-client` | `modules/slots/llm/client/default.nix` |
| `llm-proxy` | `modules/slots/llm/proxy/default.nix` |
| `mcp` | `modules/slots/mcp/default.nix` |
| `mcp-basic-memory` | `modules/slots/mcp/basic-memory/default.nix` |
| `mcp-pretty-print` | `modules/slots/mcp/pretty-print/default.nix` |
| `mcp-snoop` | `modules/slots/mcp/snoop/default.nix` |
| `nix` | `modules/slots/nix/default.nix` |
| `opencode` | `modules/slots/opencode/default.nix` |
| `rosetta-builder` | `modules/slots/rosetta-builder/default.nix` |
| `signing` | `modules/slots/signing/default.nix` |
| `ssh-access` | `modules/slots/ssh-access/default.nix` |
| `ssh-agent` | `modules/slots/ssh-agent/default.nix` |
| `zellij` | `modules/slots/zellij/default.nix` |

The `nix` name is taken by the slot port, so the old-tree `nix`/`nixpkgs` opinion becomes
`nix-config`. See the header of `modules/den/aspects/nix-config.nix`.

### From a split or a non-`default.nix` file

| Aspect | Where it comes from |
|---|---|
| `homebrew` | The Homebrew block of `modules/universal/default.nix`, plus `kdn.homebrew.*` in `modules/universal/_options.nix`. It has no slot ancestor. |
| `homebrew-nix-managed` | The `nix-homebrew` half of the same block. It `includes` `homebrew`. |
| `nix-config` | `modules/universal/_options.nix` and `modules/universal/nix.nix`. Neither is a `default.nix`, so the auto-loader never saw them; `modules/universal/default.nix` imports them by hand. |
| `hm-bootstrap` | `modules/universal/_hm-bootstrap.nix`, the portable part. Not a `default.nix`. |
| `stylix` | `modules/universal/_stylix.nix`, the machine half. Not a `default.nix`. |
| `stylix-home` | The user half of the same file. |
| `disks-persist` | The user half of `modules/universal/disks/default.nix`. The old tree used `home-manager.sharedModules`; den partitions by scope, so the user half needs its own aspect. |
| `toolset-network-gui` | The desktop branch of `modules/universal/toolset/network/default.nix`. That branch reads `config.kdn.desktop.enable`. den keys a graphical extra on `kdn.graphical` instead, and inclusion is the switch, so the one GUI package becomes an aspect. |
| `desktop-sway-swaylock` | `modules/universal/desktop/sway/home-manager/swaylock.nix`. The old file is no `default.nix`, so the main table holds no row for it. |
| `desktop-sway-media-keys` | `modules/universal/desktop/sway/home-manager/media-keys.nix`. Same reason. |
| `desktop-sway-swayr` | `modules/universal/desktop/sway/home-manager/swayr.nix`. Same reason. |
| `desktop-sway-waybar` | `modules/universal/desktop/sway/home-manager/waybar.nix`. Same reason. |
| `net-router-dhcp` | A split of `modules/universal/networking/router/default.nix`: Kea DHCPv4 and DHCPv6. |
| `net-router-dns` | The same split: the `kresd` recursive resolver. |
| `net-router-dns-rewrites` | The same split: the local DNS rewrite set. |
| `net-router-ddns` | The same split: the dynamic-DNS client. |
| `profile-baseline-gc` | A split of `modules/universal/profile/machine/baseline/default.nix`: the store garbage-collection opinion. |
| `profile-baseline-flake-links` | The same split: the flake registry links, `nixos` alone. |
| `profile-headless-zellij` | A split of `modules/universal/headless/base/default.nix`: one tool per leaf, `homeManager` alone. |
| `profile-headless-vim` | The same split. |
| `profile-headless-wezterm` | The same split. |
| `service-k8s-management` | A split of `modules/universal/services/k8s/default.nix`: the command set of a machine that administers a cluster, without the node half. |

## Known gaps

### Two old modules get no aspect on purpose

`modules/universal/toolset/ide/default.nix` and `modules/universal/toolset/print-3d/default.nix`
hold a forward write and nothing else. `modules/den/aspects/toolset.nix:15` states the decision. A
den consumer names the aspects it wants directly, so a module that only turns other modules on has
no den counterpart. Both rows stay `not ported`, and no batch owns them.

### Three old modules still wait for a batch

| Old module | Lines | What blocks it |
|---|---|---|
| `modules/universal/profile/remote-builders/default.nix` | 327 | It reads another host's evaluated config. den has no cross-host read. `modules/den/aspects/nix-remote-builder.nix` serves the reader half and names this module as the writer a later batch ports. |
| `modules/universal/profile/hardware/rpi4/default.nix` | 209 | The den check harness runs one platform. `docs/tasks/2026-09/generalization/015-den-check-harness-platforms/definition.md` holds the blocker. |
| `modules/universal/profile/default-secrets/default.nix` | 138 | It names this repository's own secret files. An adopter needs a data-driven form first. |

Together those three hold 674 lines. With the two deliberate exclusions above, the whole remainder
is 5 files and 743 lines.

### Closed: the sway session core

Every `desktop/` row now carries an aspect. `modules/den/aspects/desktop-sway.nix` ports both halves
of the session — `desktop/sway/default.nix` and `desktop/sway/home-manager/default.nix` — and it
serves `desktop-sway-remote` from the same file. `modules/den/common/desktop-sway.nix` holds the
shared key map that eight sway aspects read.

### Closed: `kdn.security.disk-encryption` has an aspect

`modules/den/aspects/security-disk-encryption.nix` exists and the registry names it. It writes
`security.tpm2.enable = true`, which the old tree also did, and it keeps the tool-set half through
`toolset-fs-encryption`. `modules/den/aspects/disks.nix` still drops the old forward write on
purpose; its header states the reason. So a den consumer names the aspect instead of the option.

### Closed: two files declared an option outside the `kdn` namespace

`modules/universal/desktop/sway/home-manager/nwg-shell/default.nix` declares `services.nwg-shell`,
and its `nwg-panel` sub-module declares `services.nwg-shell.panel`. den serves one namespace, `kdn`,
which `modules/den/namespaces.nix` names. The port picked the two names:
`modules/den/aspects/desktop-sway-nwg.nix` declares `kdn.desktop-sway-nwg-shell` and
`kdn.desktop-sway-nwg-panel`. Both aspects emit the plain Home Manager options underneath, so the
choice cost nothing.

### Cross-module coupling shaped every port

Each aspect must be standalone. A den aspect may read another aspect's option only through
`config.kdn.<other> or { }`, and it must not write it. The old tree breaks that rule in both
directions, so each port needs a design decision first. Three couplings still shape the remainder:

- `modules/universal/desktop/default.nix` declares `kdn.desktop.enable`. 18 files of
  `modules/universal/` read `config.kdn.desktop.enable`, over 24 sites. Every read gates a graphical
  extra. den answers the whole pattern with `modules/den/common/graphical.nix`: each aspect keeps an
  own option that defaults to the shared `kdn.graphical`. That is why the row is `shared`.
- `modules/universal/profile/machine/baseline/default.nix` is the widest writer of the old tree.
  22 sites over the modules and the hosts name `kdn.profile.machine.baseline`. The port answers it
  with `includes`: `modules/den/aspects/profile-baseline.nix` turns each old `enable` write into an
  `includes` entry, so no aspect writes a sibling's option.
- `modules/universal/profile/remote-builders/default.nix` reads another host's evaluated config.
  That read has no den form yet, and it is the one coupling the port has not answered.

The remainder is now small: 5 `default.nix` files and 743 lines. Two of the five are the deliberate
`toolset` exclusions above, at 34 and 35 lines. `refresh.sh measure` prints the file count and the
line total from the `not ported` rows of the main table, so the two figures cannot disagree with the
table.

## How to refresh this doc

Run each command from the repository root. Do not trust a number above; re-measure it.

```bash
# The commit stack state this file must name. The topmost line that names den is the last den change.
jj --config signing.behavior=drop log -r '::@ & mutable()' --no-graph \
  -T 'change_id.short(12) ++ " | " ++ commit_id.short(8) ++ " | " ++ if(empty,"empty","content") ++ " | " ++ description.first_line() ++ "\n"'

# Every count above, plus the two-way proof against the registry.
bash .cache/agent-notes/sub-agent-outputs/mapping-doc-refresh/refresh.sh measure

# Registry name count. Parse the attribute set, never the directory: one file serves many names.
awk '/^  aspectModules = \{/,/^  \};/' modules/den/lib.nix \
  | sed -nE 's|^ +([A-Za-z0-9_-]+) = \./aspects/.*|\1|p' | sort -u | wc -l

# Distinct targets, then the file half and the directory half. A directory target holds a
# `default.nix`, so `find -name '*.nix'` counts it and a top-level `ls` does not.
awk '/^  aspectModules = \{/,/^  \};/' modules/den/lib.nix \
  | sed -nE 's|^ +[A-Za-z0-9_-]+ = (\./aspects/[A-Za-z0-9_.-]+);|\1|p' | sort -u | tee /tmp/t | wc -l
grep -cE  '\.nix$' /tmp/t     # targets that are a file
grep -cvE '\.nix$' /tmp/t     # targets that are a directory

# Top-level aspect files, and the ones the registry does not name yet.
ls modules/den/aspects/*.nix | wc -l
comm -23 \
  <(ls modules/den/aspects/*.nix | sed 's|modules/den/|./|' | sort -u) \
  <(grep -oE '\./aspects/[A-Za-z0-9_.-]+\.nix' modules/den/lib.nix | sort -u)

# Files that serve more than one name, and names that differ from their file base name.
awk '/^  aspectModules = \{/,/^  \};/' modules/den/lib.nix \
  | sed -nE 's|^ +[A-Za-z0-9_-]+ = \./aspects/([A-Za-z0-9_.-]+);|\1|p' \
  | sort | uniq -c | awk '$1 > 1'
awk '/^  aspectModules = \{/,/^  \};/' modules/den/lib.nix \
  | sed -nE 's|^ +([A-Za-z0-9_-]+) = \./aspects/([A-Za-z0-9_.-]+);|\1 \2|p' \
  | awk '{ b=$2; sub(/\.nix$/,"",b); if (b != $1) print $1 " -> aspects/" $2 }'

# Row count per status, straight from this file. A main-table row has five cells, so `NF` is 6.
# The exclusions table has two cells, so a count over the path alone over-reports by three.
awk -F'|' 'NF == 6 && $2 ~ /^ `modules\/universal\// {
    st = $5; gsub(/^ +| +$|`/, "", st); c[st]++; t++
  }
  END { for (k in c) printf "%-18s %s\n", k, c[k]; printf "%-18s %s\n", "TOTAL", t }' \
  docs/den-universal-mapping.md | sort

# The remainder, and its line total. Pull the path with awk. A `sed` over the whole row leaves the
# markdown pipes in place, and `xargs wc -l` then fails once per pipe and prints `0 total`.
awk -F'|' 'NF == 6 && $2 ~ /^ `modules\/universal\// {
    st = $5; gsub(/^ +| +$|`/, "", st)
    if (st != "not ported") next
    p = $2; gsub(/^ +| +$|`/, "", p); print p
  }' docs/den-universal-mapping.md | xargs wc -l

# Rewrite the Status column from the registry. Fill every `den aspect` cell first.
bash .cache/agent-notes/sub-agent-outputs/mapping-doc-refresh/refresh.sh fix

# Old-tree module count. The second command excludes the private subtree; replace
# <PRIVATE> with the name of that directory.
find modules/universal -name default.nix | wc -l
find modules/universal -name default.nix -not -path '*/<PRIVATE>/*' | wc -l

# The `kdn.*` prefix one module declares.
grep -ohE '^\s*options\.kdn\.[A-Za-z0-9_.-]+|^\s{4}kdn\.[A-Za-z0-9_.-]+ = \{' <file>

# Line count of one area, aspect or not. Every area of `modules/universal/` still holds its files.
find modules/universal/profile -name '*.nix' | xargs wc -l | tail -1

# Coupling: how many files read one option.
grep -rln 'config\.kdn\.desktop\.enable' modules/universal --include='*.nix' | wc -l
```

The `<PRIVATE>` path in the second `find` command is the private-subtree filter. Keep it; every
count in this file excludes that subtree.

## Related documents

- `modules/den/README.md` — the aspect architecture and the class model.
- `docs/den-for-adopters.md` — how an external adopter imports an aspect.
- `docs/tasks/2026-09/generalization/definition.md` — the umbrella task this port belongs to.
- `.agents/rules/slots-standalone.md` — the standalone rule that `checks/standalone.nix` enforces
  over both `modules/slots/` and `modules/den/aspects/`.
