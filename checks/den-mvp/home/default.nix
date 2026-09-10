# The standalone home-manager configurations. They belong to no den host. See ../README.md.
#
# This mirrors ../devenv/default.nix. `den.lib.aspects.resolve "homeManager" <aspect>` takes a plain
# class name, so a standalone route needs no den entity, no user and no host.
#
# The two routes answer different questions. This one asks whether the `homeManager` half of an
# aspect is a valid home-manager module on its own — the shape an external adopter uses. The host
# route asks whether den forwards that half to `home-manager.users.<user>` inside a real system.
# Both matter, and only the host route can hit den's scope-partition trap.
{
  den,
  inputs,
  kdn,
  lib,
  ...
}:
let
  # One aspect list, shared by every standalone home configuration.
  aspects = [
    kdn.devenv-cli

    # The `homeManager`-only aspect. The standalone route is the shape an external adopter uses.
    kdn.ssh-agent
  ];

  mkHome =
    name: system:
    let
      isDarwin = lib.hasSuffix "darwin" system;
    in
    inputs.home-manager.lib.homeManagerConfiguration {
      pkgs = import inputs.nixpkgs { inherit system; };
      modules = map (den.lib.aspects.resolve "homeManager") aspects ++ [
        {
          # A standalone home-manager evaluation carries no user entity, so these three come from
          # here instead of from `den.batteries.define-user`.
          home.username = "dev";
          home.homeDirectory = if isDarwin then "/Users/dev" else "/home/dev";
          home.stateVersion = "26.11";

          # The same reason as in ../users/default.nix: the aspect enables no shell, so the test
          # subject does.
          programs.bash.enable = true;
          programs.zsh.enable = true;
          programs.fish.enable = true;
        }
      ];
    };
in
{
  # den declares no `flake.<output>` option by itself, and it ships one per output name it knows.
  # `homeConfigurations` is not one of them, so declare it here. The devenv class does the same for
  # `flake.devenvShells` — see ../../../modules/den/classes/devenv.nix.
  options.flake.homeConfigurations = lib.mkOption {
    type = lib.types.lazyAttrsOf lib.types.raw;
    default = { };
    description = "One evaluated standalone home-manager configuration per system.";
  };

  config.flake.homeConfigurations = lib.mapAttrs mkHome {
    home-darwin = "aarch64-darwin";
    home-linux = "x86_64-linux";
  };
}
