{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.services.omada;
in {
  options.kdn.services.omada = {
    enable = lib.mkEnableOption "Omada Software Controller";

    dataDir = lib.mkOption {
      type = with lib.types; path;
      default = "/var/lib/omada";
    };
    user = lib.mkOption {
      type = with lib.types; str;
      default = "omada";
    };
    group = lib.mkOption {
      type = with lib.types; str;
      default = "omada";
    };
  };

  config = lib.mkIf cfg.enable {
    users.groups."${cfg.group}" = {};

    users.users."${cfg.user}" = {
      description = "Omada Software Controller";
      group = cfg.group;
      home = cfg.dataDir;
      createHome = true;
      isSystemUser = true;
    };

    kdn.hw.disks.persist."sys/data".directories = [
      {
        directory = cfg.dataDir;
        user = cfg.user;
        group = cfg.group;
        mode = "0755";
      }
    ];
  };
}
