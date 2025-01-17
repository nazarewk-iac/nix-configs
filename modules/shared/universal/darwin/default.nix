{
  lib,
  pkgs,
  config,
  self,
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
        "`kdn.darwin` enabled, but we're on ${pkgs.stdenv.hostPlatform.system}!"
        enable;
    };

    type = lib.mkOption {
      type = with lib.types; enum [null "home-manager" "nix-darwin"];
      default =
        if pkgs.stdenv.isDarwin && config ? home
        then "home-manager"
        else if pkgs.stdenv.isDarwin && config ? system
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
}
