{ lib, pkgs, config, ... }:
let
  cfg = config.kdn.locale;
in
{
  options.kdn.locale = {
    timezone = lib.mkOption {
      type = lib.types.str;
      default = "Europe/Warsaw";
    };

    primary = lib.mkOption {
      type = lib.types.str;
      default = "en_US.UTF-8";
    };

    # en_GB - Monday as first day of week
    time = lib.mkOption {
      type = lib.types.str;
      default = "en_GB.UTF-8";
    };
  };

  config = {
    # LOCALE
    i18n.supportedLocales = [
      # see https://sourceware.org/git/?p=glibc.git;a=blob;f=localedata/SUPPORTED
      "en_US.UTF-8/UTF-8"
      "en_GB.UTF-8/UTF-8"
      "pl_PL.UTF-8/UTF-8"
      "pl_PL/ISO-8859-2"
    ];
    i18n.defaultLocale = cfg.primary;
    i18n.extraLocaleSettings = {
      LC_TIME = cfg.time;
    };
    time.timeZone = cfg.timezone;
  };
}
