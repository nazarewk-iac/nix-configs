---
type: Reference
description: Maps every modules/universal module to its modules/den/aspects counterpart, with a port status per module and the gaps that remain.
timestamp: 2026-09-11T15:14:23+02:00
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
| Last den change id | `syttukpqqunz` (commit `fa451b9b`) |
| Its description | `feat(den): port the development area as thirty aspects` |
| `@` | one undescribed change with content — this document refresh |
| Measured | 2026-09-11 |

Batch 9 landed. `modules/den/aspects/` holds 30 `dev-*.nix` files, and `modules/den/lib.nix`
registers all 30 names. No aspect file waits for a registry entry now. Batch 8 writes no file yet;
its names come from its plan at
`.cache/agent-notes/sub-agent-outputs/layerc-b8-programs/plan.md`.

Two trees carry a private subtree. Every count below excludes it.

## Summary

| Status | Old modules | Meaning |
|---|---|---|
| `ported` | 86 | An aspect exists and `modules/den/lib.nix` registers it. |
| `in flight` | 0 | Batch 9 landed, so no module holds this status. |
| `queued (batch 8)` | 40 | Neither the file nor the registry entry exists. The plan names the aspect. |
| `not ported` | 46 | No aspect, no plan yet. |
| `excluded` | 4 | A deliberate decision keeps it out of den. |
| **Total** | **176** | Every `modules/universal/**/default.nix`, private subtree excluded. |

Registry side, measured on the same stack:

| Item | Value |
|---|---|
| Names in `modules/den/lib.nix` | 110 |
| Distinct files those 110 names point at | 98 |
| `.nix` files in `modules/den/aspects/` | 98 |
| Unregistered files | 0 |

The registry is a **many-to-one** map. `toolset.nix` serves 11 names, `fs.nix` serves 3, and
`disks.nix` plus `disks-persist.nix` split one old module into two aspects.

Four more registry names differ from the file base name:

| Registry name | File |
|---|---|
| `emulation-wine` | `aspects/emulation.nix` |
| `packaging-asdf` | `aspects/packaging.nix` |
| `monitoring-prometheus-stack` | `aspects/monitoring.nix` |
| `outputs-host` | `aspects/outputs.nix` |

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
| `modules/universal/desktop/base/default.nix` | `kdn.desktop.base` | — | `not ported` |
| `modules/universal/desktop/default.nix` | `kdn.desktop` | — | `not ported` |
| `modules/universal/desktop/kde/default.nix` | `kdn.desktop.kde` | — | `not ported` |
| `modules/universal/desktop/remote-server/default.nix` | `kdn.desktop.remote-server` | — | `not ported` |
| `modules/universal/desktop/sway/default.nix` | `kdn.desktop.sway` | — | `not ported` |
| `modules/universal/desktop/sway/home-manager/default.nix` | `kdn.desktop.sway` | — | `not ported` |
| `modules/universal/desktop/sway/home-manager/kanshi/default.nix` | `kdn.desktop.sway.kanshi` | — | `not ported` |
| `modules/universal/desktop/sway/home-manager/nwg-shell/default.nix` | `services.nwg-shell` | — | `not ported` |
| `modules/universal/desktop/sway/home-manager/nwg-shell/nwg-panel/default.nix` | `services.nwg-shell.panel` | — | `not ported` |
| `modules/universal/desktop/sway/home-manager/swaync/default.nix` | — | — | `not ported` |
| `modules/universal/desktop/sway/remote/default.nix` | `kdn.desktop.sway.remote` | — | `not ported` |

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
| `modules/universal/headless/base/default.nix` | `kdn.headless.base` | — | `not ported` |

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
| `modules/universal/networking/router/default.nix` | `kdn.networking.router` | — | `not ported` |
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
| `modules/universal/profile/hardware/darwin-utm-guest/default.nix` | `kdn.profile.hardware.darwin-utm-guest` | — | `not ported` |
| `modules/universal/profile/hardware/dell-e5470/default.nix` | `kdn.profile.hardware.dell-e5470` | — | `not ported` |
| `modules/universal/profile/hardware/rpi4/default.nix` | `kdn.profile.hardware.rpi4` | — | `not ported` |
| `modules/universal/profile/machine/baseline/default.nix` | `kdn.profile.machine.baseline` | — | `not ported` |
| `modules/universal/profile/machine/basic/default.nix` | `kdn.profile.machine.basic` | — | `not ported` |
| `modules/universal/profile/machine/desktop/default.nix` | `kdn.profile.machine.desktop` | — | `not ported` |
| `modules/universal/profile/machine/dev/default.nix` | `kdn.profile.machine.dev` | — | `not ported` |
| `modules/universal/profile/machine/gaming/default.nix` | `kdn.profile.machine.gaming` | — | `not ported` |
| `modules/universal/profile/machine/hetzner/default.nix` | `kdn.profile.machine.hetzner` | — | `not ported` |
| `modules/universal/profile/machine/workstation/default.nix` | `kdn.profile.machine.workstation` | — | `not ported` |
| `modules/universal/profile/remote-builders/default.nix` | `kdn.profile.remote-builders` | — | `excluded` |
| `modules/universal/profile/user/bn/default.nix` | `kdn.profile.user.bn` | — | `not ported` |
| `modules/universal/profile/user/kdn/default.nix` | `kdn.profile.user.kdn` | — | `not ported` |
| `modules/universal/profile/user/sn/default.nix` | `kdn.profile.user.sn` | — | `not ported` |

### programs

| old module | `kdn.*` prefix | den aspect | Status |
|---|---|---|---|
| `modules/universal/programs/atuin/default.nix` | `kdn.programs.atuin` | `program-atuin` | `queued (batch 8)` |
| `modules/universal/programs/beeper/default.nix` | `kdn.programs.beeper` | `program-beeper` | `queued (batch 8)` |
| `modules/universal/programs/blender/default.nix` | `kdn.programs.blender` | `program-blender` | `queued (batch 8)` |
| `modules/universal/programs/browsers-launcher/default.nix` | `kdn.programs.browsers-launcher` | `program-browsers-launcher` | `queued (batch 8)` |
| `modules/universal/programs/chrome/default.nix` | `kdn.programs.chrome` | `program-chrome` | `queued (batch 8)` |
| `modules/universal/programs/chromium/default.nix` | `kdn.programs.chromium` | `program-chromium` | `queued (batch 8)` |
| `modules/universal/programs/dconf/default.nix` | `kdn.programs.dconf` | `program-dconf` | `queued (batch 8)` |
| `modules/universal/programs/direnv/default.nix` | `kdn.programs.direnv` | `program-direnv` | `queued (batch 8)` |
| `modules/universal/programs/editors/photo/default.nix` | `kdn.programs.editors.photo` | `program-editors-photo` | `queued (batch 8)` |
| `modules/universal/programs/editors/video/default.nix` | `kdn.programs.editors.video` | `program-editors-video` | `queued (batch 8)` |
| `modules/universal/programs/element/default.nix` | `kdn.programs.matrix` | `program-matrix` | `queued (batch 8)` |
| `modules/universal/programs/ente-photos/default.nix` | `kdn.programs.ente-photos` | `program-ente-photos` | `queued (batch 8)` |
| `modules/universal/programs/firefox/default.nix` | `kdn.programs.firefox` | `program-firefox` | `queued (batch 8)` |
| `modules/universal/programs/fish/default.nix` | `kdn.programs.fish` | `program-fish` | `queued (batch 8)` |
| `modules/universal/programs/gnupg/default.nix` | `kdn.programs.gnupg` | `program-gnupg` | `queued (batch 8)` |
| `modules/universal/programs/handlr/default.nix` | `kdn.programs.handlr` | `program-handlr` | `queued (batch 8)` |
| `modules/universal/programs/kdeconnect/default.nix` | `kdn.programs.kdeconnect` | `program-kdeconnect` | `queued (batch 8)` |
| `modules/universal/programs/keepass/default.nix` | `kdn.programs.keepass` | `program-keepass` | `queued (batch 8)` |
| `modules/universal/programs/keepassxc/default.nix` | `kdn.programs.keepassxc` | `program-keepassxc` | `queued (batch 8)` |
| `modules/universal/programs/logseq/default.nix` | `kdn.programs.logseq` | `program-logseq` | `queued (batch 8)` |
| `modules/universal/programs/midnight-commander/default.nix` | `kdn.programs.midnight-commander` | `program-midnight-commander` | `queued (batch 8)` |
| `modules/universal/programs/nextcloud-client/default.nix` | `kdn.programs.nextcloud-client` | `program-nextcloud-client` | `queued (batch 8)` |
| `modules/universal/programs/nix-index/default.nix` | `kdn.programs.nix-index` | `program-nix-index` | `queued (batch 8)` |
| `modules/universal/programs/obs-studio/default.nix` | `kdn.programs.obs-studio` | `program-obs-studio` | `queued (batch 8)` |
| `modules/universal/programs/office/default.nix` | `kdn.programs.office` | `program-office` | `queued (batch 8)` |
| `modules/universal/programs/orca-slicer/default.nix` | `kdn.programs.orca-slicer` | `program-orca-slicer` | `queued (batch 8)` |
| `modules/universal/programs/photoprism/default.nix` | `kdn.programs.photoprism` | `program-photoprism` | `queued (batch 8)` |
| `modules/universal/programs/rambox/default.nix` | `kdn.programs.rambox` | `program-rambox` | `queued (batch 8)` |
| `modules/universal/programs/signal/default.nix` | `kdn.programs.signal` | `program-signal` | `queued (batch 8)` |
| `modules/universal/programs/slack/default.nix` | `kdn.programs.slack` | `program-slack` | `queued (batch 8)` |
| `modules/universal/programs/spotify/default.nix` | `kdn.programs.spotify` | `program-spotify` | `queued (batch 8)` |
| `modules/universal/programs/ssh-client/default.nix` | `kdn.programs.ssh-client` | `program-ssh-client` | `queued (batch 8)` |
| `modules/universal/programs/terminal-ide/default.nix` | `kdn.programs.terminal-ide` | `program-terminal-ide` | `queued (batch 8)` |
| `modules/universal/programs/thunderbird/default.nix` | `kdn.programs.thunderbird` | `program-thunderbird` | `queued (batch 8)` |
| `modules/universal/programs/tidal/default.nix` | `kdn.programs.tidal` | `program-tidal` | `queued (batch 8)` |
| `modules/universal/programs/torrent/default.nix` | `kdn.programs.torrent` | `program-torrent` | `queued (batch 8)` |
| `modules/universal/programs/weechat/default.nix` | `kdn.programs.weechat` | `program-weechat` | `queued (batch 8)` |
| `modules/universal/programs/wofi/default.nix` | `kdn.programs.wofi` | `program-wofi` | `queued (batch 8)` |
| `modules/universal/programs/ydotool/default.nix` | `kdn.programs.ydotool` | `program-ydotool` | `queued (batch 8)` |
| `modules/universal/programs/zsh/default.nix` | `kdn.programs.zsh` | `program-zsh` | `queued (batch 8)` |

### security

| old module | `kdn.*` prefix | den aspect | Status |
|---|---|---|---|
| `modules/universal/security/disk-encryption/default.nix` | `kdn.security.disk-encryption` | — | `not ported` |
| `modules/universal/security/secrets/age/default.nix` | `kdn.security.secrets.age` | — | `not ported` |
| `modules/universal/security/secrets/default.nix` | `kdn.security.secrets` | `secrets` | `ported` |
| `modules/universal/security/secrets/sops/default.nix` | `kdn.security.secrets.sops` | — | `not ported` |
| `modules/universal/security/secure-boot/default.nix` | `kdn.security.secure-boot` | — | `not ported` |

### services

| old module | `kdn.*` prefix | den aspect | Status |
|---|---|---|---|
| `modules/universal/services/caddy/default.nix` | `kdn.services.caddy` | `service-caddy` | `ported` |
| `modules/universal/services/coredns/default.nix` | `kdn.services.coredns` | `service-coredns` | `ported` |
| `modules/universal/services/home-assistant/default.nix` | `kdn.services.home-assistant` | `service-home-assistant` | `ported` |
| `modules/universal/services/iperf3/default.nix` | `kdn.services.iperf3` | `service-iperf3` | `ported` |
| `modules/universal/services/k8s/controlplane/loadbalancer/default.nix` | — | — | `not ported` |
| `modules/universal/services/k8s/default.nix` | `kdn.services.k8s` | — | `not ported` |
| `modules/universal/services/k8s/kubeadm/default.nix` | `kdn.services.k8s.kubeadm` | — | `not ported` |
| `modules/universal/services/k8s/node/default.nix` | `kdn.services.k8s.node` | — | `not ported` |
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
| `modules/universal/virtualisation/microvm/guest/default.nix` | `kdn.virtualisation.microvm.guest` | — | `not ported` |
| `modules/universal/virtualisation/microvm/host/default.nix` | `kdn.virtualisation.microvm.host` | — | `not ported` |
| `modules/universal/virtualisation/vagrant/default.nix` | `kdn.virtualisation.vagrant` | `virt-vagrant` | `ported` |

## The four deliberate exclusions

| Old module | Reason |
|---|---|
| `modules/universal/default.nix` | It is the auto-loader plus the tree-wide opinions. den needs no loader. Two parts of it **do** reach den: the Homebrew concern becomes `homebrew` and `homebrew-nix-managed`, and `_options.nix` plus `nix.nix` become `nix-config`. |
| `modules/universal/helpers/default.nix` | `kdn.helpers` is a script bag of this repository. An adopter wants none of it. |
| `modules/universal/profile/remote-builders/default.nix` | It reads another host's evaluated config. den has no cross-host read, and an adopter has no such host set. |
| `modules/universal/env/default.nix` | den ships no `kdn.env.*` by design. Design B makes each target write the native option, and the old `apply` filter moves to `modules/den/common/filter-packages.nix`. |

## Reverse: den aspects that no old module backs

24 registry names have no dedicated `modules/universal/**/default.nix` behind them. 19 come from
`modules/slots/`, and 5 come from a split or from a non-`default.nix` file.

### From `modules/slots/` (19)

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

### From a split or a non-`default.nix` file (5)

| Aspect | Where it comes from |
|---|---|
| `homebrew` | The Homebrew block of `modules/universal/default.nix`, plus `kdn.homebrew.*` in `modules/universal/_options.nix`. It has no slot ancestor. |
| `homebrew-nix-managed` | The `nix-homebrew` half of the same block. It `includes` `homebrew`. |
| `nix-config` | `modules/universal/_options.nix` and `modules/universal/nix.nix`. Neither is a `default.nix`, so the auto-loader never saw them; `modules/universal/default.nix` imports them by hand. |
| `disks-persist` | The user half of `modules/universal/disks/default.nix`. The old tree used `home-manager.sharedModules`; den partitions by scope, so the user half needs its own aspect. |
| `toolset-network-gui` | The desktop branch of `modules/universal/toolset/network/default.nix`. That branch reads `config.kdn.desktop.enable`. den has no desktop aspect, and inclusion is the switch, so the one GUI package becomes an aspect. |

## Known gaps

### `kdn.security.disk-encryption` has no aspect and no owner

One file declares it: `modules/universal/security/disk-encryption/default.nix`, 27 lines. Three
files write it with `lib.mkDefault`: `modules/universal/disks/config.nix:556`,
`modules/universal/profile/machine/baseline/default.nix:130`, and `hosts/install-iso/default.nix:33`.
`modules/den/aspects/disks.nix` drops that forward write on purpose; its header states the reason at
line 35. The old module does exactly two things: it turns `kdn.toolset.fs.encryption` on, and it
writes `security.tpm2.enable = true`. The tool-set half survives, because
`modules/den/aspects/toolset.nix:342` lists `kdn.toolset-fs-encryption` in `toolset-fs.includes`. The
TPM half does **not**: a grep for `tpm2` over `modules/den/` returns two package names in
`toolset.nix` and no `security.tpm2` write at all. So a den consumer that wants a TPM-bound LUKS
volume must write `security.tpm2.enable` itself today.

### Two files declare an option outside the `kdn` namespace

`modules/universal/desktop/sway/home-manager/nwg-shell/default.nix` declares `services.nwg-shell`,
and `.../nwg-shell/nwg-panel/default.nix` declares `services.nwg-shell.panel`. den serves one
namespace, `kdn`, which `modules/den/namespaces.nix` names. An aspect emits a plain nixpkgs option
freely, so both modules can port. But neither option name survives as an aspect option, so the port
must first choose a `kdn.*` name for each. That choice is open.

### Cross-module coupling makes the remainder hard

Each aspect must be standalone. A den aspect may read another aspect's option only through
`config.kdn.<other> or { }`, and it must not write it. The remaining 46 modules break that rule in
both directions, so each one needs a design decision before a port. The measured couplings:

- `modules/universal/desktop/default.nix` declares `kdn.desktop.enable`. 18 files of
  `modules/universal/` read `config.kdn.desktop.enable`, over 24 sites. Every read gates a graphical
  extra. The landed aspects already convert each read into an own option — `hw-audio`, `hw-qmk`,
  `toolset-network-gui` and `dev-k8s` each state that in their headers.
- `modules/universal/networking/default.nix` declares `kdn.networking`, the interface graph. 9 sites
  read `config.kdn.networking.*`, and `services/k8s/controlplane/loadbalancer/default.nix` reads
  another host's copy of it.
- `modules/universal/networking/netbird/default.nix` declares `kdn.networking.netbird.clients`.
  13 sites over the modules and the hosts read or write it.
- `modules/universal/services/k8s/` holds 4 modules and 422 lines. 14 sites read `kdn.services.k8s`,
  and `controlplane/loadbalancer/default.nix` declares no option of its own.
- `modules/universal/toolset/ide/default.nix` holds a forward write only. Two files turn it on:
  `profile/machine/dev/default.nix:55` and `headless/base/default.nix:73`. Its own `config` half
  writes `kdn.programs.*`, which batch 8 owns.
- `modules/universal/headless/base/default.nix`, 280 lines, both writes `kdn.toolset.ide.enable` and
  is turned on by `profile/machine/baseline/default.nix:120`. So it sits in the middle of a chain.
- `modules/universal/profile/machine/baseline/default.nix` is the widest writer of the remainder.
  9 sites read `kdn.profile.machine.baseline`, and the module writes `kdn.headless.base.enable` and
  `kdn.security.disk-encryption.enable`.

Line counts of the remainder, so you can size a batch: `networking/` 8 files 2869 lines (with
`router/default.nix` alone at 1833), `profile/` 15 files 2828 lines, `desktop/` 11 `default.nix`
files 1754 lines (17 `.nix` files, 2350 lines), `security/` 4 files 531 lines, `services/k8s` 4
files 422 lines, `headless/` 1 file 280 lines, `virtualisation/microvm/` 2 files 162 lines,
`toolset/` 2 files 69 lines. All 50 remaining `default.nix` files hold 9376 lines.

## How to refresh this doc

Run each command from the repository root. Do not trust a number above; re-measure it.

```bash
# The commit stack state this file must name. The topmost `feat(den)` line is the last den commit.
jj --config signing.behavior=drop log -r '::@ & mutable()' --no-graph \
  -T 'change_id.short(12) ++ " | " ++ commit_id.short(8) ++ " | " ++ if(empty,"empty","content") ++ " | " ++ description.first_line() ++ "\n"'

# Registry name count, and the distinct files those names point at.
grep -cE '^\s+[a-zA-Z0-9_-]+ = \./aspects/' modules/den/lib.nix
grep -oE '\./aspects/[a-zA-Z0-9_.-]+' modules/den/lib.nix | sort -u | wc -l

# Aspect files on disk, and the ones the registry does not name yet.
find modules/den/aspects -name '*.nix' | wc -l
comm -23 \
  <(ls modules/den/aspects/*.nix | sed 's|modules/den/|./|' | sort -u) \
  <(grep -oE '\./aspects/[a-zA-Z0-9_.-]+\.nix' modules/den/lib.nix | sort -u)

# Old-tree module count. The second command excludes the private subtree; replace
# <PRIVATE> with the name of that directory.
find modules/universal -name default.nix | wc -l
find modules/universal -name default.nix -not -path '*/<PRIVATE>/*' | wc -l

# The `kdn.*` prefix one module declares.
grep -ohE '^\s*options\.kdn\.[A-Za-z0-9_.-]+|^\s{4}kdn\.[A-Za-z0-9_.-]+ = \{' <file>

# Line count of an area that has no aspect yet.
find modules/universal/networking -name '*.nix' | xargs wc -l | tail -1

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
