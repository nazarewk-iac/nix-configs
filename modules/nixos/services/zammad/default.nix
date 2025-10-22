{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.services.zammad;
  uCfg = config.services.zammad;
in {
  options.kdn.services.zammad = {
    enable = lib.mkEnableOption "zammad helpdesk management software";

    host = lib.mkOption {
      type = with lib.types; str;
      default = "127.0.0.13";
    };

    user = lib.mkOption {
      type = with lib.types; str;
      default = "zammad";
      readOnly = true;
    };
    group = lib.mkOption {
      type = with lib.types; str;
      default = "zammad";
      readOnly = true;
    };

    redis.fullName = lib.mkOption {
      type = with lib.types; str;
      default = "redis-${uCfg.redis.name}";
      readOnly = true;
    };
    redis.host = lib.mkOption {
      type = with lib.types; str;
      readOnly = true;
      # `localhost` is enforced by the module
      default = "localhost";
    };
    redis.address = lib.mkOption {
      type = with lib.types; str;
      readOnly = true;
      default = "127.0.0.1";
    };
  };

  config = lib.mkIf cfg.enable {
    services.zammad.enable = true;
    services.zammad.host = cfg.host;
    services.zammad.port = 80;

    kdn.services.postgresql.enable = true;
    services.zammad.database.createLocally = true;

    services.zammad.redis.host = cfg.redis.host;
    services.zammad.redis.port = 46201;
    services.zammad.redis.createLocally = true;
    services.redis.servers."${uCfg.redis.name}" = {
      user = cfg.user;
      group = cfg.group;
      bind = cfg.redis.address;
    };
    systemd.services.zammad-web.serviceConfig.AmbientCapabilities = [
      "CAP_NET_BIND_SERVICE"
    ];

    kdn.hw.disks.persist."sys/data".directories = [
      {
        directory = "/var/lib/${cfg.redis.fullName}";
        user = cfg.user;
        group = cfg.group;
        mode = "0750";
      }
      {
        directory = uCfg.dataDir;
        user = cfg.user;
        group = cfg.group;
        mode = "0750";
      }
    ];
  };
}
