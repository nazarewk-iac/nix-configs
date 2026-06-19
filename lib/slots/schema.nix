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
  options.modules = {
    nixos = slot "NixOS system modules";
    darwin = slot "nix-darwin modules";
    home = slot "home-manager modules (all users via sharedModules)";
    devenv = slot "devenv.sh modules";
    users = lib.mkOption {
      type = lib.types.attrsOf lib.types.deferredModule;
      default = { };
      description = "Per-user home-manager modules keyed by username";
    };
  };
}
