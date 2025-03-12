{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.services.postgresql;
  uCfg = config.services.postgresql;
in {
  options.kdn.services.postgresql = {
    enable = lib.mkEnableOption "postgresql database";

    user = lib.mkOption {
      type = with lib.types; str;
      default = "postgres";
      readOnly = true;
    };
    group = lib.mkOption {
      type = with lib.types; str;
      default = "postgres";
      readOnly = true;
    };
  };

  config = lib.mkIf cfg.enable {
    services.postgresql.enable = true;

    kdn.hw.disks.persist."sys/data".directories = [
      {
        directory = uCfg.dataDir;
        user = cfg.user;
        group = cfg.group;
        mode = "0750";
      }
    ];
  };
}
