{ lib
, pkgs
, config
, ...
}:
let
  cfg = config.kdn.networking.netmaker.server;

  envFile.generated.config = "${cfg.configDir}/env.generated";
  envFile.generated.secrets = "${cfg.secretsDir}/env.generated";
  envFile.user.config = "${cfg.configDir}/env.editable";
  envFile.user.secrets = "${cfg.secretsDir}/env.editable";

  configureScript = pkgs.writeShellApplication {
    name = "netmaker-configure";
    runtimeInputs = with pkgs; [
      coreutils
      gawk
      gnugrep
      gnused
    ];
    text = ''
      COREFILE="${cfg.dataDir}/config/dnsconfig/Corefile"
      MQ_PASSWORD_FILE="${cfg.mq.passwordFile}"

      SECRETS="${envFile.generated.secrets}"
      ENV="${envFile.generated.config}"

      ${builtins.readFile ./netmaker-configure.sh}
    '';
  };
  internalAddressType = lib.types.submodule ({ config, ... }: {
    options = {
      host = lib.mkOption {
        type = with lib.types; str;
      };
      port = lib.mkOption {
        type = with lib.types; port;
      };
      addr = lib.mkOption {
        type = with lib.types; str;
        readOnly = true;
        default = "${config.host}:${builtins.toString config.port}";
      };
    };
  });
  internalAddressOption = { host ? cfg.internalAddress, port }: lib.mkOption {
    type = internalAddressType;
    default = { inherit host port; };
  };
in
{
  options.kdn.networking.netmaker.server = {
    enable = lib.mkEnableOption "Netmaker server";

    domain = lib.mkOption {
      type = with lib.types; str;
    };

    # TODO: use it in Caddy certs?
    email = lib.mkOption {
      type = with lib.types; str;
    };

    internalAddress = lib.mkOption {
      type = with lib.types; str;
      default = "127.0.0.2";
    };

    verbosity = lib.mkOption {
      type = with lib.types; enum [ 1 2 3 4 ];
      default = 4;
    };

    telemetry.enable = lib.mkEnableOption "sending telemetry to Netmaker developers";

    package = lib.mkOption {
      type = with lib.types; package;
      default =
        if cfg.installType == "ce"
        then pkgs.kdn.netmaker
        else pkgs.kdn.netmaker-pro;
    };

    installType = lib.mkOption {
      type = with lib.types; enum [
        "ce"
        "pro"
      ];
      default = "ce";
    };

    dataDir = lib.mkOption {
      type = with lib.types; path;
      default = "/var/lib/netmaker";
    };
    stunList = lib.mkOption {
      type = with lib.types; listOf str;
      default = [
        "stun1.netmaker.io:3478"
        "stun2.netmaker.io:3478"
        "stun1.l.google.com:19302"
        "stun2.l.google.com:19302"
      ];
    };
    configDir = lib.mkOption {
      type = with lib.types; path;
      default = "/etc/netmaker";
    };
    secretsDir = lib.mkOption {
      type = with lib.types; path;
      default = "${cfg.configDir}/secrets";
    };
    jwtValidityDuration = lib.mkOption {
      type = with lib.types; int;
      default = 24 * 60 * 60;
    };

    cors.maxAge = lib.mkOption {
      type = with lib.types; int;
      default = 5 * 60;
    };

    api.domain = lib.mkOption {
      type = with lib.types; str;
      default = "api.${cfg.domain}";
    };
    api.internal = internalAddressOption { port = 8081; };

    ui.enable = lib.mkOption {
      type = with lib.types; bool;
      default = true;
    };
    ui.domain = lib.mkOption {
      type = with lib.types; str;
      default = "dashboard.${cfg.domain}";
    };
    ui.package = lib.mkOption {
      type = with lib.types; package;
      default = pkgs.kdn.netmaker-ui;
    };
    ui.amuiUrl = lib.mkOption {
      type = with lib.types; str;
      default = "https://account.staging.netmaker.io";
    };
    ui.intercomAppID = lib.mkOption {
      type = with lib.types; str;
      default = "";
    };

    env.server = lib.mkOption {
      type = with lib.types; attrsOf (nullOr str);
      default = { };
      apply = lib.attrsets.filterAttrs (n: v: v != null);
    };
    envFiles.server = lib.mkOption {
      type = with lib.types; listOf path;
      default = [ ];
    };

    firewall.ports = {
      networks.start = lib.mkOption {
        type = with lib.types; port;
        default = 51821;
      };
      networks.capacity = lib.mkOption {
        type = with lib.types; port;
        default = 10;
      };
    };

    webserver.type = lib.mkOption {
      type = with lib.types; enum [
        "caddy"
      ];
      default = "caddy";
    };

    db.type = lib.mkOption {
      type = with lib.types; enum [
        "sqlite"
      ];
      default = "sqlite";
    };

    coredns.internal = internalAddressOption { port = 53; };

    mq.type = lib.mkOption {
      type = with lib.types; enum [
        "mosquitto"
        "external"
      ];
      default = "mosquitto";
    };
    mq.internal = internalAddressOption { port = 8883; };
    mq.domain = lib.mkOption {
      type = with lib.types; str;
      default = "broker.${cfg.domain}";
    };
    mq.username = lib.mkOption {
      type = with lib.types; str;
      default = "netmaker";
    };
    mq.passwordFile = lib.mkOption {
      type = with lib.types; path;
      default = "${cfg.secretsDir}/MQ_PASSWORD";
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      environment.systemPackages = with pkgs.kdn; [
        nmctl
      ];

      networking.firewall = with cfg.firewall.ports; {
        allowedTCPPorts = [ cfg.coredns.internal.port ];
        allowedUDPPorts = [ cfg.coredns.internal.port ];
        allowedUDPPortRanges = [{
          from = networks.start;
          to = networks.start + networks.capacity - 1;
        }];
      };
    }
    {
      systemd.tmpfiles.rules = [
        "d ${cfg.secretsDir} 1700 root root"
        "f ${envFile.generated.config} 1644 root root"
        "f ${envFile.generated.secrets} 1600 root root"
        "f ${envFile.user.config} 1644 root root"
        "f ${envFile.user.secrets} 1600 root root"
      ];
      kdn.networking.netmaker.server.envFiles.server = [
        envFile.generated.config
        envFile.generated.secrets
        envFile.user.config
        envFile.user.secrets
      ];
      kdn.networking.netmaker.server.env.server = {
        VERBOSITY = builtins.toString cfg.verbosity;
        TELEMETRY = if cfg.telemetry.enable then "on" else "off";
        STUN_LIST = builtins.concatStringsSep "," cfg.stunList;
        SERVER_NAME = cfg.domain;
        API_PORT = builtins.toString cfg.api.internal.port;
        SERVER_API_CONN_STRING = "${cfg.api.domain}:443";
        SERVER_HOST = cfg.api.internal.host;
        SERVER_HTTP_HOST = cfg.api.domain;
        BROKER_TYPE = cfg.mq.type;
        BROKER_ENDPOINT = "wss://${cfg.mq.domain}";
        # don't set to anything, see https://github.com/nazarewk/netmaker/blob/9ca6b44228847d246dd5617b73f69ec26778f396/servercfg/serverconf.go#L215-L223
        COREDNS_ADDR = lib.mkDefault null;
        DATABASE = cfg.db.type;
        JWT_VALIDITY_DURATION = builtins.toString cfg.jwtValidityDuration;
        SERVER_BROKER_ENDPOINT = "ws://${cfg.mq.internal.addr}";
        MQ_USERNAME = cfg.mq.username;
      };

      systemd.services.netmaker-configure = {
        serviceConfig.Type = "oneshot";
        serviceConfig.RemainAfterExit = true;
        script = lib.getExe configureScript;
      };

      # based on https://github.com/gravitl/netclient/blob/b9ea9c9841f01297955b03c2b5bbf4b5139aa40c/daemon/systemd_linux.go#L14-L30
      systemd.services.netmaker = {
        description = "Netmaker Daemon";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        requires = [ "netmaker-configure.service" ];
        wantedBy = [ "multi-user.target" ];

        environment = cfg.env.server;
        serviceConfig.EnvironmentFile = cfg.envFiles.server;
        serviceConfig.WorkingDirectory = cfg.dataDir;
        serviceConfig.ExecStart = lib.getExe cfg.package;

        serviceConfig.Restart = "on-failure";
        serviceConfig.RestartSec = "15s";
      };
    }
    {
      # CoreDNS related config
      services.coredns.enable = true;
      systemd.services.coredns.requires = [ "netmaker-configure.service" ];
      services.coredns.extraArgs = [
        "-conf=${cfg.dataDir}/config/dnsconfig/Corefile"
      ];
    }
    (lib.mkIf (cfg.webserver.type == "caddy") {
      kdn.services.caddy.enable = true;
      systemd.services.caddy.requires = [ "netmaker-configure.service" ];
      systemd.services.netmaker.after = [ "caddy.service" ];
      systemd.services.netmaker.requires = [ "caddy.service" ];

      services.caddy.virtualHosts."https://${cfg.api.domain}".extraConfig = ''
        header {
          Access-Control-Allow-Origin *
          Access-Control-Max-Age ${builtins.toString cfg.cors.maxAge}
          -Server
        }
        reverse_proxy http://${cfg.api.internal.addr}
      '';
    })
    (lib.mkIf (cfg.webserver.type == "caddy" && cfg.ui.enable) {
      # see https://github.com/gravitl/netmaker/blob/630c95c48b43ac8b0cdff1c3de13339c8b322889/docker/Caddyfile#L1-L20
      services.caddy.virtualHosts."https://${cfg.ui.domain}".extraConfig = ''
        header {
          Access-Control-Allow-Origin https://${cfg.ui.domain}
          Access-Control-Max-Age ${builtins.toString cfg.cors.maxAge}
          Strict-Transport-Security "max-age=31536000;"
          X-XSS-Protection "1; mode=block"
          X-Frame-Options "SAMEORIGIN"
          X-Robots-Tag "none"
          -Server
        }

        handle /nmui-config.js {
          header Content-Type text/javascript
          respond <<EOF
          window.NMUI_AMUI_URL='${cfg.ui.amuiUrl}';
          window.NMUI_BACKEND_URL='https://${cfg.api.domain}';
          window.NMUI_INTERCOM_APP_ID='${cfg.ui.intercomAppID}';
          EOF
        }

        handle {
          # see https://github.com/gravitl/netmaker-ui-2/blob/b305a96fc19160346f7cd59439d4625f262aaedf/nginx.conf#L7-L7
          try_files {path} {path}/ /index.html
          root * ${cfg.ui.package}/var/www
          file_server
        }
      '';
    })
    (lib.mkIf (cfg.db.type == "sqlite") { })
    (lib.mkIf (cfg.mq.type == "mosquitto" && cfg.webserver.type == "caddy") {
      # see https://www.reddit.com/r/selfhosted/comments/14wqwa4/comment/jrp07gq/?utm_source=share&utm_medium=web3x&utm_name=web3xcss&utm_term=1&utm_content=share_button
      services.caddy.virtualHosts."https://${cfg.mq.domain}".extraConfig = ''
        reverse_proxy ${cfg.mq.internal.addr} {
          stream_timeout 6h
          stream_close_delay 1m
        }
      '';
    })
    (lib.mkIf (cfg.mq.type == "mosquitto") {
      systemd.services.mosquitto.requires = [ "netmaker-configure.service" ];
      systemd.services.netmaker.after = [ "mosquitto.service" ];
      systemd.services.netmaker.requires = [ "mosquitto.service" ];

      services.mosquitto.enable = true;
      services.mosquitto.listeners = [{
        address = cfg.mq.internal.host;
        port = cfg.mq.internal.port;
        users."${cfg.mq.username}".passwordFile = cfg.mq.passwordFile;
        settings.allow_anonymous = false;
        settings.protocol = "websockets";
      }];
    })
  ]);
}
