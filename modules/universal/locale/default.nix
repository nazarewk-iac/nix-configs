{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.locale;
in {
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
}
