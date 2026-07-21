{ lib, ... }:
let
  # Evaluate a list of slot-style modules and return a renderer.
  # slotModules: list of modules that assign to options.{nixos,darwin,home,devenv,users}
  # specialArgs: extra args threaded into the evalModules (e.g. pkgs, inputs)
  mkSlots =
    {
      slotModules,
      specialArgs ? { },
    }:
    let
      evaluated = (
        lib.evalModules {
          modules = [ ./schema.nix ] ++ slotModules;
          inherit specialArgs;
        }
      );
    in
    evaluated
    // {
      # Returns a module value for a target slot — usable directly in nixosSystem /
      # darwinSystem / devenv.lib.mkShell modules lists.
      #
      # Imports a small module declaring a read-only `slots` option carrying the full raw
      # kdn-slots `config`, alongside the target's own rendered module — so individual slot
      # modules can expose kdn.* values (e.g. a built package) to the downstream consumer
      # without hand-rolling an option declaration in every target's own schema. Kept as a
      # sibling import (not merged into the target's own `config`) so it can never clobber a
      # real target option from within.
      renderTarget = target: {
        imports = [
          {
            options.slots = lib.mkOption {
              type = lib.types.raw;
              readOnly = true;
              description = "The full evaluated kdn-slots config, exposed read-only for downstream consumers.";
            };
            config.slots = evaluated.config;
          }
          (evaluated.config.${target} or { })
        ];
      };

      # Returns attrset of username -> { imports = [userModule]; } ready for
      # home-manager.users.<name> assignment.
      renderUsers = lib.mapAttrs (_: m: { imports = [ m ]; }) evaluated.config.users;
    };
in
{
  inherit mkSlots;
}
