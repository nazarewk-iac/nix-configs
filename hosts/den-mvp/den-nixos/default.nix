# A build-only den host for the `nixos` class.
#
# It mirrors a real NixOS workstation at the **slot** level. See ../README.md for the compare
# commands and for the reason this directory is invisible to `flake.hostConfigurations`.
#
# This host never activates. It evaluates and it builds. It carries no personal data, no disk
# layout, no hardware, and no machine uses its name.
#
# No aspect is ported for the `nixos` class yet, so this host carries only the NixOS minimum. It is
# the landing place for the first ported NixOS aspect: add it to `includes` below.
{ den, ... }:
{
  # `x86_64-linux` matches the real NixOS hosts, so a comparison uses the same platform. den derives
  # `class = "nixos"` from the system suffix, and its default `instantiate` is
  # `inputs.nixpkgs.lib.nixosSystem` — an input name this repo does use, so no override is needed.
  den.hosts.x86_64-linux.den-nixos = { };

  den.aspects.den-nixos.includes = [
    # Add a ported NixOS aspect here.
  ];

  den.aspects.den-nixos.nixos =
    { config, ... }:
    {
      networking.hostName = "den-nixos";

      # `system.build.toplevel` needs a root file system, or an assertion stops the evaluation.
      # `tmpfs` needs no disk, no label and no UUID, so it names no real hardware.
      fileSystems."/" = {
        device = "none";
        fsType = "tmpfs";
      };

      # NixOS enables GRUB by default and then asserts that `devices` is not empty. This host never
      # boots, so it needs no boot loader at all.
      boot.loader.grub.enable = false;

      # Track the nixpkgs release this flake pins, because a build-only host keeps no state to
      # stay compatible with.
      system.stateVersion = config.system.nixos.release;
    };
}
