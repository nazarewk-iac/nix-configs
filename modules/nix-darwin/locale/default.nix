{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.locale;
in {
  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        time.timeZone = cfg.timezone;
        homebrew.caskArgs.language = builtins.concatStringsSep "," cfg.shorts;

        environment.variables = {
          LANG = cfg.primary;
          LC_TIME = cfg.time;
          LANGUAGE = cfg.primary;
          LC_ALL = cfg.primary;
        };
      }
    ]
  );
}
