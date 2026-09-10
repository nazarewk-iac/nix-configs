# A build-only NixOS host. It never activates and it names no hardware. See ../README.md.
{ den, ... }:
{
  # `x86_64-linux` matches the real NixOS hosts, so a comparison uses the same platform. den derives
  # `class = "nixos"` from the system suffix, and its default `instantiate` is
  # `inputs.nixpkgs.lib.nixosSystem` — an input name this repo does use, so no override is needed.
  den.hosts.x86_64-linux.host-nixos = {
    # `homeManager` must be explicit. den's default is `[ "user" ]` alone. `../users/default.nix`
    # holds the `dev` aspect.
    users.dev.classes = [
      "user"
      "homeManager"
    ];
  };

  den.aspects.host-nixos.includes = [
    # `gh` emits into the `devenv` target only, so it changes no NixOS option.
    den.aspects.gh

    # The first aspect that reaches this host's `nixos` target. It also delivers the `devenv` half
    # to this host's shell. Its `homeManager` half arrives through the `dev` user instead, because
    # den partitions by scope — see ../users/default.nix.
    den.aspects.devenv-cli
  ];

  den.aspects.host-nixos.nixos =
    { config, ... }:
    {
      networking.hostName = "host-nixos";

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
