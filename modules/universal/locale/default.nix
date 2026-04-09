{
  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}:
let
  cfg = config.kdn.locale;
in
{
  options.kdn.locale = {
    enable = lib.mkEnableOption "locale setup";

    timezone = lib.mkOption {
      type = lib.types.str;
      default = "Europe/Warsaw";
    };

    primary = lib.mkOption {
      type = lib.types.str;
      default = "en_GB.UTF-8";
    };

    extra = lib.mkOption {
      type = with lib.types; listOf str;
      default = [
        # see https://sourceware.org/git/?p=glibc.git;a=blob;f=localedata/SUPPORTED
        "C.UTF-8/UTF-8"
        "en_US.UTF-8/UTF-8"
        "en_GB.UTF-8/UTF-8"
        "pl_PL.UTF-8/UTF-8"
        "pl_PL/ISO-8859-2"
      ];
    };

    shorts = lib.mkOption {
      type = with lib.types; listOf str;
      default = [
        "en-GB"
        "en-US"
        "en"
        "pl-PL"
        "pl"
      ];
    };

    # en_GB - Monday as first day of week
    time = lib.mkOption {
      type = lib.types.str;
      default = "en_GB.UTF-8";
    };

    userDirs = lib.mkOption {
      type = lib.types.str;
      default = cfg.primary;
    };
  };

  config = lib.mkMerge [
    # shared darwin-nixos: propagate locale settings to HM
    (kdnConfig.util.ifHMParent {
      home-manager.sharedModules = [ { kdn.locale = builtins.mapAttrs (name: lib.mkDefault) cfg; } ];
    })
    # nixos
    (kdnConfig.util.ifTypes [ "nixos" ] (
      lib.mkIf cfg.enable {
        i18n.supportedLocales = cfg.extra;
        i18n.defaultLocale = cfg.primary;
        i18n.extraLocaleSettings = {
          LC_TIME = cfg.time;
          LANGUAGE = cfg.primary;
          LC_ALL = cfg.primary;
        };
        time.timeZone = cfg.timezone;
      }
    ))
    # darwin
    (kdnConfig.util.ifTypes [ "darwin" ] (
      lib.mkIf cfg.enable {
        time.timeZone = cfg.timezone;
        homebrew.caskArgs.language = builtins.concatStringsSep "," cfg.shorts;
        environment.variables = {
          LANG = cfg.primary;
          LC_TIME = cfg.time;
          LANGUAGE = cfg.primary;
          LC_ALL = cfg.primary;
        };
      }
    ))
    # home-manager
    (kdnConfig.util.ifHM (
      lib.mkMerge [
        {
          home.sessionVariables.TZ = cfg.timezone;
          xdg.configFile."user-dirs.locale".source = pkgs.writeText "locale.conf" cfg.userDirs;
        }
        (lib.mkIf config.xdg.userDirs.enable {
          xdg.configFile."user-dirs.dirs".force = true;
          xdg.configFile."locale.conf".force = true;
          xdg.configFile."user-dirs.locale".force = true;
        })
        (
          let
            # reuse NixOS module at https://github.com/NixOS/nixpkgs/blob/f2dd2b8e197cc54d0eb1c741f549d94600df91c0/nixos/modules/config/i18n.nix
            config = {
              i18n.defaultLocale = cfg.primary;
              i18n.extraLocaleSettings = {
                #LANG = cfg.primary; # handled by `i18n.defaultLocale`
                LC_TIME = cfg.time;
                LANGUAGE = cfg.primary;
                LC_ALL = cfg.primary;
              };
            };
          in
          {
            xdg.configFile."locale.conf".source = pkgs.writeText "locale.conf" ''
              LANG=${config.i18n.defaultLocale}
              ${lib.concatStringsSep "\n" (
                lib.mapAttrsToList (n: v: "${n}=${v}") config.i18n.extraLocaleSettings
              )}
            '';
            home.sessionVariables = {
              LANG = config.i18n.defaultLocale;
            }
            // config.i18n.extraLocaleSettings;
          }
        )
      ]
    ))
  ]; # end config mkMerge
}
