{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.locale;
in {
  config = lib.mkMerge [
    {home-manager.sharedModules = [{kdn.locale = builtins.mapAttrs (name: lib.mkDefault) cfg;}];}
  ];
}
