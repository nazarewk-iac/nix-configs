# The `profile/machine/workstation` module of the old tree, as one den aspect.
#
# The old module stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# `profile-workstation` is the top bundle. It reaches `profile-desktop` and `profile-dev`, it adds
# sway, the remote desktop, the media editors and two virtualisation aspects, and it carries the
# clevis initrd unlock plus `diffoscope`.
#
# ## Class list: `nixos`, `darwin` and `homeManager`
#
# The old module holds `diffoscope` outside every context guard, so all three classes carry a
# package. The `nixos` class also carries seahorse, clevis and offlineimap.
#
# ## What the port changes
#
# 1. **`enable` goes.** Inclusion is the switch.
# 2. **The 14 turned-on `enable` writes become `includes` entries.**
# 3. **Five `false` writes go.** The old module sets `kdn.desktop.kde.enable`,
#    `kdn.development.kernel.enable`, `kdn.monitoring.prometheus-stack.enable`,
#    `kdn.services.caddy.enable` and `kdn.development.cloud.azure.enable` to `false`. In den an
#    aspect is off when nothing names it, so a `false` write has no den equivalent. Naming those
#    five aspects would turn them on, which is the opposite of the old behaviour.
# 4. **`kdn.monitoring.prometheus-stack.caddy.grafana` goes.** The write is dead — the very next
#    line sets the stack to `false` — and its value is a personal host name.
# 5. **Three sub-option writes go.** `kdn.desktop.sway.remote.enable`,
#    `kdn.programs.gnupg.pinentry` and `kdn.networking.tailscale.auth_key` each set a sub-option of
#    another aspect. An aspect writes no option of another aspect, so the consumer wires all three.
# 6. **`dev-jetbrains` arrives here.** The old `toolset/ide` module turns JetBrains on only when a
#    desktop is present. This bundle is the one that is both a desktop and a development machine.
# 7. **`boot.initrd.availableKernelModules = [ ]` goes.** An empty list adds nothing, because the
#    option concatenates.
# 8. **`kdn.env.packages` goes.** Each target writes the native package option of its own class.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.**
# 2. **No reachable `enable` option.**
# 3. **No custom module argument.** Each target module below takes `lib` and `pkgs` only.
{ kdn, ... }:
let
  filtered = lib: pkgs: import ../common/filter-packages.nix { inherit lib; } [ pkgs.diffoscope ];

  hostTarget =
    { lib, pkgs, ... }:
    {
      environment.systemPackages = filtered lib pkgs;
    };
in
{
  kdn.profile-workstation.includes = [
    kdn.desktop-remote-server
    kdn.desktop-sway
    kdn.dev-android
    kdn.dev-jetbrains
    kdn.profile-desktop
    kdn.profile-dev
    kdn.program-editors-photo
    kdn.program-editors-video
    kdn.program-nix-index
    kdn.program-obs-studio
    kdn.toolset-diagrams
    kdn.toolset-logs-processing
    kdn.virt-libvirtd
    kdn.virt-vagrant
  ];

  kdn.profile-workstation.nixos =
    { lib, pkgs, ... }:
    {
      environment.systemPackages = filtered lib pkgs;

      programs.seahorse.enable = lib.mkDefault true;
      services.offlineimap.install = lib.mkDefault true;

      # A TPM or a network unlock of the encrypted root, so a reboot needs no keyboard.
      boot.initrd.clevis.enable = lib.mkDefault true;

      boot.binfmt.emulatedSystems = [
        # "wasm32-wasi"
        # "wasm64-wasi"
      ];
    };

  kdn.profile-workstation.darwin = hostTarget;

  kdn.profile-workstation.homeManager =
    { lib, pkgs, ... }:
    {
      home.packages = filtered lib pkgs;
    };
}
