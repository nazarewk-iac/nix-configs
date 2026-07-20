{ lib, ... }:
let
  slot =
    desc:
    lib.mkOption {
      type = lib.types.deferredModule;
      default = { };
      description = desc;
    };
in
{
  options.nixos = slot "NixOS system modules";
  options.darwin = slot "nix-darwin modules";
  options.home = slot "home-manager modules (all users via sharedModules)";
  options.devenv = slot "devenv.sh modules";
  options.users = lib.mkOption {
    type = lib.types.attrsOf lib.types.deferredModule;
    default = { };
    description = "Per-user home-manager modules keyed by username";
  };
}
