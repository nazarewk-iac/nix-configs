{ lib
, pkgs
, config
, ...
}:
let
  cfg = config.kdn.networking.netmaker.server;

  configureEnvFile = "${cfg.configDir}/env.generated";
  secretsEnvFile = "${cfg.secretsDir}/env.generated";

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

      SECRETS="${secretsEnvFile}"
      ENV="${configureEnvFile}"

      ${builtins.readFile ./netmaker-configure.sh}
    '';
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

    mode = lib.mkOption {
      type = with lib.types; enum [
        "nm-quick"
        "nixos"
      ];
      default = "nixos";
    };

    internalAddress = lib.mkOption {
      type = with lib.types; str;
      default = "127.0.0.2";
    };

    package = lib.mkOption {
      type = with lib.types; package;
      default = pkgs.kdn.netmaker;
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

    api.domain = lib.mkOption {
      type = with lib.types; str;
      default = "api.${cfg.domain}";
    };
    api.port = lib.mkOption {
      type = with lib.types; port;
      default = 8081;
    };

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
      dns = lib.mkOption {
        type = with lib.types; port;
        default = 53;
      };
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

    mq.type = lib.mkOption {
      type = with lib.types; enum [
        "mosquitto"
      ];
      default = "mosquitto";
    };
    mq.public.port = lib.mkOption {
      type = with lib.types; port;
      default = 8883;
    };
    mq.internal.port = lib.mkOption {
      type = with lib.types; port;
      default = 1883;
    };
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
    (lib.mkIf (cfg.mode == "nixos") {
      systemd.tmpfiles.rules = [
        "d ${cfg.secretsDir} 1700 root root"
      ];
      kdn.networking.netmaker.server.envFiles.server = [
        configureEnvFile
        secretsEnvFile
      ];
      kdn.networking.netmaker.server.env.server = {
        # from https://github.com/gravitl/netmaker/blob/630c95c48b43ac8b0cdff1c3de13339c8b322889/compose/docker-compose.yml#L5-L27
        STUN_LIST = builtins.concatStringsSep "," cfg.stunList;
        NM_DOMAIN = cfg.domain;
        SERVER_NAME = cfg.domain;
        API_PORT = builtins.toString cfg.api.port;
        SERVER_API_CONN_STRING = "${cfg.api.domain}:443";
        SERVER_HOST = builtins.toString cfg.internalAddress;
        SERVER_HTTP_HOST = builtins.toString cfg.internalAddress;
        BROKER_ENDPOINT = "wss://${cfg.mq.domain}";
        COREDNS_ADDR = builtins.toString cfg.internalAddress;
        DATABASE = cfg.db.type;
        JWT_VALIDITY_DURATION = builtins.toString cfg.jwtValidityDuration;
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
        script = lib.getExe cfg.package;
        serviceConfig.Restart = "on-failure";
        serviceConfig.RestartSec = "15s";
        serviceConfig.WorkingDirectory = cfg.dataDir;
      };
    })
    (lib.mkIf (cfg.mode == "nixos") {
      services.coredns.enable = true;
      systemd.services.coredns.requires = [ "netmaker-configure.service" ];
      services.coredns.extraArgs = [
        "-conf=${cfg.dataDir}/config/dnsconfig/Corefile"
      ];
    })
    (lib.mkIf (cfg.mode == "nixos" && cfg.webserver.type == "caddy") {
      kdn.services.caddy.enable = true;
      systemd.services.caddy.requires = [ "netmaker-configure.service" ];

      services.caddy.virtualHosts."https://${cfg.api.domain}".extraConfig = ''
        reverse_proxy http://${cfg.internalAddress}:${builtins.toString cfg.api.port}
      '';
      # Jan 18 20:32:35 wg-0 caddy[140830]: Error: adapting config using caddyfile: server block 2, key 0 (wss://broker.subsidize-stroller.kdn.im): determining listener address: the scheme wss:// is only supported in browsers; use https:// instead
      services.caddy.virtualHosts."https://${cfg.mq.domain}".extraConfig = ''
        # Jan 18 20:28:34 wg-0 caddy[140329]: Error: adapting config using caddyfile: parsing caddyfile tokens for 'reverse_proxy': parsing upstream 'ws://127.0.0.2:8883': the scheme ws:// is only supported in browsers; use http:// instead, at /etc/caddy/caddy_config:57
        reverse_proxy http://${cfg.internalAddress}:${builtins.toString cfg.mq.public.port}
      '';
    })
    (lib.mkIf (cfg.mode == "nixos" && cfg.webserver.type == "caddy" && cfg.ui.enable) {
      # see https://github.com/gravitl/netmaker/blob/630c95c48b43ac8b0cdff1c3de13339c8b322889/docker/Caddyfile#L1-L20
      services.caddy.virtualHosts."https://${cfg.ui.domain}".extraConfig = ''
        header {
          # Enable cross origin access to *.${cfg.domain}
          Access-Control-Allow-Origin *.${cfg.domain}
          # Enable HTTP Strict Transport Security (HSTS)
          Strict-Transport-Security "max-age=31536000;"
          # Enable cross-site filter (XSS) and tell browser to block detected attacks
          X-XSS-Protection "1; mode=block"
          # Disallow the site to be rendered within a frame on a foreign domain (clickjacking protection)
          X-Frame-Options "SAMEORIGIN"
          # Prevent search engines from indexing
          X-Robots-Tag "none"
          # Remove the server name
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
    (lib.mkIf (cfg.mode == "nixos" && cfg.db.type == "sqlite") { })
    (lib.mkIf (cfg.mode == "nixos" && cfg.mq.type == "mosquitto") {
      systemd.services.mosquitto.requires = [ "netmaker-configure.service" ];

      services.mosquitto.enable = true;
      services.mosquitto.listeners = [
        {
          address = cfg.internalAddress;
          port = cfg.mq.public.port;
          users."${cfg.mq.username}".hashedPassword = cfg.mq.passwordFile;
          settings.allow_anonymous = false;
          settings.protocol = "websockets";
        }
        {
          address = cfg.internalAddress;
          port = cfg.mq.internal.port;
          users."${cfg.mq.username}".passwordFile = cfg.mq.passwordFile;
          settings.allow_anonymous = false;
          settings.protocol = "websockets";
        }
      ];
      kdn.networking.netmaker.server.env.server.SERVER_BROKER_ENDPOINT = "ws://localhost:${builtins.toString cfg.mq.internal.port}";
      kdn.networking.netmaker.server.env.server.MQ_USERNAME = cfg.mq.username;
    })
    {
      environment.systemPackages = with pkgs.kdn; [
        nmctl
      ];

      networking.firewall = with cfg.firewall.ports; {
        allowedTCPPorts = [
          dns
        ];
        allowedUDPPorts = [
          dns
        ];
        allowedUDPPortRanges = [{
          from = networks.start;
          to = networks.start + networks.capacity - 1;
        }];
      };
    }
    (lib.mkIf (cfg.mode == "nm-quick") {
      kdn.services.caddy.enable = lib.mkForce false;

      kdn.programs.direnv.enable = true; # to work with it

      kdn.virtualisation.containers.enable = true;
      virtualisation.podman.dockerSocket.enable = true;

      # TODO: move Caddy out of docker-compose?
      # TODO: fix certificates issuance (switch to DNS challenge?)
      # TODO: issue certificates for wildcard domain instead, see https://caddyserver.com/docs/caddyfile/patterns#wildcard-certificates
      environment.systemPackages = [
        pkgs.kdn.netmaker-scripts
        pkgs.sqlite
      ] ++ pkgs.kdn.netmaker-scripts.passthru.deps;
    })
  ]);
}
