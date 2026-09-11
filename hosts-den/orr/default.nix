# The first real den host. It is the parallel twin of `hosts/orr/`.
#
# ## Why the name repeats the old tree's name
#
# The output prefix keeps the two apart — `nixosConfigurations.orr` against `denConfigurations.orr`
# — so one short name serves both and the compare command stays short:
#
#     nix eval --json '.#nixosConfigurations.orr.config.nix.settings.substituters'
#     nix eval --json '.#denConfigurations.orr.config.nix.settings.substituters'
#
# The old host file is untouched and it keeps working. `flake.nix` reads `./hosts` alone and it
# needs a `meta.json`, so this directory is invisible to the old loader.
#
# ## No `meta.json`
#
# The host file states its own system and its own class. `den.hosts.<system>.<name>` carries the
# system in the attribute path, and den derives the class from the `-linux` suffix. The `class` line
# below states it anyway, so a reader needs no den source.
#
# ## What it holds today
#
# The two aspects of batch 1, the two host-class aspects of batch 2, and the minimum a NixOS
# evaluation asserts: a root file system and a disabled GRUB. It is a skeleton, not yet a replica of
# `hosts/orr/`. Each later batch adds the aspects it ports, and the compare command above is the
# gate.
#
# `kdn.apps` is absent on purpose. That aspect claims the `homeManager` class alone, and this host
# names no user yet.
{ kdn, ... }:
{
  den.hosts.aarch64-linux.orr.class = "nixos";

  den.aspects.orr.includes = [
    kdn.hw-usbip
    kdn.hw-yubikey
    kdn.locale
    kdn.nix-config
    kdn.nix-remote-builder
    kdn.secrets
  ];

  den.aspects.orr.nixos = {
    networking.hostName = "orr";

    # NixOS asserts a root file system and a non-empty `boot.loader.grub.devices`. Both lines come
    # from ../../checks/den-mvp/host-nixos/default.nix, and neither names hardware.
    fileSystems."/" = {
      device = "none";
      fsType = "tmpfs";
    };
    boot.loader.grub.enable = false;

    system.stateVersion = "26.05";
  };
}
