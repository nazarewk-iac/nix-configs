{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.kdn.locale;
in
{
  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        # LOCALE
        i18n.supportedLocales = cfg.extra;
        i18n.defaultLocale = cfg.primary;
        i18n.extraLocaleSettings = {
          #LANG = cfg.primary; # handled by `i18n.defaultLocale`
          LC_TIME = cfg.time;
          LANGUAGE = cfg.primary;
          LC_ALL = cfg.primary;
        };
        time.timeZone = cfg.timezone;
      }
    ]
  );
}
