{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.darwin;
in {
  options.kdn.darwin = {
    enable = lib.mkOption {
      type = with lib.types; bool;

      default = cfg.type != null;
      apply = enable:
        lib.trivial.throwIf (enable && cfg.type == null)
        "`kdn.darwin` enabled, but we're on ${pkgs.stdenv.system}!"
        enable;
    };

    type = lib.mkOption {
      type = with lib.types; enum [null "nix-darwin"];
      default =
        if pkgs.stdenv.isDarwin && config ? system && config.system ? darwinRelease
        then "nix-darwin"
        else null;
    };

    dirs.apps.src = lib.mkOption {
      type = with lib.types; str;
    };
    dirs.apps.base = lib.mkOption {
      type = with lib.types; str;
    };
  };

  config.kdn.types = lib.lists.optional (cfg.type != null) cfg.type;
}
