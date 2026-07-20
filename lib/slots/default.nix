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
      # Returns the deferredModule value for a target slot — a plain module
      # directly usable in nixosSystem / darwinSystem / devenv.lib.mkShell modules lists.
      renderTarget = target: evaluated.config.${target} or { };

      # Returns attrset of username -> { imports = [userModule]; } ready for
      # home-manager.users.<name> assignment.
      renderUsers = lib.mapAttrs (_: m: { imports = [ m ]; }) evaluated.config.users;
    };
in
{
  inherit mkSlots;
}
