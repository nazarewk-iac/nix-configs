{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.nix.remote-builder;
in {
  options.kdn.nix.remote-builder = {
    enable = lib.mkEnableOption "remote builder config";

    name = lib.mkOption {
      type = with lib.types; str;
      default = "kdn-nix-remote-build";
    };
    description = lib.mkOption {
      type = with lib.types; str;
      default = "kdn's remote Nix builder";
    };

    user.id = lib.mkOption {
      type = with lib.types; int;
      default = 25839;
    };
    user.name = lib.mkOption {
      type = with lib.types; str;
      default = cfg.name;
    };
    group.name = lib.mkOption {
      type = with lib.types; str;
      default = cfg.name;
    };
    group.id = lib.mkOption {
      type = with lib.types; int;
      default = cfg.user.id;
    };
  };
}
