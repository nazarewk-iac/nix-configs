{
  lib,
  pkgs,
  config,
  osConfig,
  ...
}: let
  cfg = config.kdn.locale;
  osCfg = osConfig.kdn.locale;
in {
  options.kdn.locale = {
    timezone = lib.mkOption {
      type = lib.types.str;
      default = osCfg.timezone;
    };

    primary = lib.mkOption {
      type = lib.types.str;
      default = osCfg.primary;
    };

    # en_GB - Monday as first day of week
    time = lib.mkOption {
      type = lib.types.str;
      default = osCfg.time;
    };

    userDirs = lib.mkOption {
      type = lib.types.str;
      default = osCfg.userDirs;
    };
  };

  config = lib.mkMerge [
    {
      home.sessionVariables.TZ = cfg.timezone;
      xdg.configFile."user-dirs.locale".source = pkgs.writeText "locale.conf" cfg.userDirs;
    }
    {
      xdg.configFile."user-dirs.dirs".force = true;
      xdg.configFile."locale.conf".force = true;
      xdg.configFile."user-dirs.locale".force = true;
    }
    (let
      # reuse NixOS module at at https://github.com/NixOS/nixpkgs/blob/f2dd2b8e197cc54d0eb1c741f549d94600df91c0/nixos/modules/config/i18n.nix
      config = {
        i18n.defaultLocale = cfg.primary;
        i18n.extraLocaleSettings = {
          #LANG = cfg.primary; # handled by `i18n.defaultLocale`
          LC_TIME = cfg.time;
          LANGUAGE = cfg.primary;
          LC_ALL = cfg.primary;
        };
      };
    in {
      xdg.configFile."locale.conf".source =
        pkgs.writeText "locale.conf"
        ''
          LANG=${config.i18n.defaultLocale}
          ${lib.concatStringsSep "\n" (lib.mapAttrsToList (n: v: "${n}=${v}") config.i18n.extraLocaleSettings)}
        '';
      home.sessionVariables =
        {
          LANG = config.i18n.defaultLocale;
        }
        // config.i18n.extraLocaleSettings;
    })
  ];
}
