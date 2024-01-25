{ lib
, pkgs
, config
, ...
}:
let
  cfg = config.services.netmaker;

  envFile.generated.config = "${cfg.configDir}/env.generated";
  envFile.generated.secrets = "${cfg.secretsDir}/env.generated";
  envFile.user.config = "${cfg.configDir}/env";
  envFile.user.secrets = "${cfg.secretsDir}/env";
in
{
  options.services.netmaker = {
    enable = lib.mkEnableOption "Netmaker Server";

    debug = lib.mkEnableOption "configuring everything with the most verbose log level";
    debugTools = lib.mkOption {
      type = with lib.types; bool;
      default = cfg.debug;
      description = lib.mdDoc ''
        Install additional debugging tools:
        - `mqttui`
        - `netmaker-mqttui` script
      '';
    };

    domain = lib.mkOption {
      type = with lib.types; str;
      description = lib.mdDoc ''
        Base external domain to use for Netmaker deployment, used in:
        - `services.netmaker.api.domain` (defaults to: `api.` prefix)
        - `services.netmaker.ui.domain` (defaults to: `dashboard.` prefix)
        - `services.netmaker.mqtt.domain` (defaults to: `broker.` prefix)
      '';
    };

    email = lib.mkOption {
      type = with lib.types; str;
      description = lib.mdDoc ''
        Email address to (currently) use for certificato registration.
      '';
    };

    package = lib.mkOption {
      type = with lib.types; package;
      default =
        if cfg.installType == "ce"
        then pkgs.netmaker
        else pkgs.netmaker-pro;
      description = lib.mdDoc ''
        Package providing `netmaker` and `nmctl` binaries.
      '';
    };

    internalListenAddress = lib.mkOption {
      type = with lib.types; str;
      default = "127.0.0.2";
      description = lib.mdDoc ''
        An address services will be listening on before being proxied
      '';
    };

    verbosity = lib.mkOption {
      type = with lib.types; enum [ 1 2 3 4 ];
      default = 1;
      description = lib.mdDoc ''
        Verbosity level of Netmaker Server logging.
      '';
    };

    telemetry = lib.mkEnableOption "sending telemetry to Netmaker developers";

    environment = lib.mkOption {
      type = with lib.types; attrsOf str;
      default = { };
      apply = envAttrs: pkgs.writeText "environment-env" (lib.trivial.pipe envAttrs [
        (lib.attrsets.mapAttrsToList (name: value: "${name}=${lib.strings.escapeShellArg value}"))
        (builtins.concatStringsSep "\n")
      ]);
      description = lib.mdDoc ''
        Additional environment variables to set on Netmaker Server
      '';
    };

    environmentFiles = lib.mkOption {
      type = with lib.types; listOf path;
      default = [ ];
    };

    config = lib.mkOption {
      type = with lib.types; anything;
      description = lib.mdDoc ''
        Content of Netmaker configuration file.

        see for more information:
        - https://github.com/gravitl/netmaker/blob/dc8f9b1bc74d262669bf96fab5f0e545f5906432/config/config.go
      '';
      apply = value: pkgs.writeText "netmaker-config.json" (builtins.toJSON value);
    };

    installType = lib.mkOption {
      type = with lib.types; enum [
        "ce"
        "pro"
      ];
      default = "ce";
      description = lib.mdDoc ''
        Type of the installation: `ce` for Community and `pro` for Professional.

        `pro` requires additional configuration not covered by the module, for reference see the [code search](https://github.com/search?q=repo%3Agravitl%2Fnetmaker+%22%24INSTALL_TYPE%22&type=code)
      '';
    };

    dataDir = lib.mkOption {
      type = with lib.types; path;
      default = "/var/lib/netmaker";
      description = lib.mdDoc ''
        Netmaker data directory, currently simply a working directory the server is running in.
        It contains following known directories and files:
        - `config/dnsconfig/netmaker.hosts`
        - `config/dnsconfig/Corefile`

        Current state can be found in [this GitHub search](https://github.com/search?q=repo%3Agravitl%2Fnetmaker+%22os.Getwd%28%29%22&type=code)
      '';
    };

    configDir = lib.mkOption {
      type = with lib.types; path;
      default = "/etc/netmaker";
      description = lib.mdDoc ''
        A configuration directory to (currently) put NixOS module related configuration files in.

        Following configuration files are used by default:
        - `${lib.strings.removePrefix cfg.configDir envFile.user.config}` - user editable environment variables
        - `${lib.strings.removePrefix cfg.configDir envFile.user.secrets}` - user editable sensitive environment variables
        - `${lib.strings.removePrefix cfg.configDir envFile.generated.config}` - generated environment variables
        - `${lib.strings.removePrefix cfg.configDir envFile.generated.secrets}` - generated sensitive environment variables
      '';
    };

    secretsDir = lib.mkOption {
      type = with lib.types; path;
      default = "${cfg.configDir}/secrets";
      description = lib.mdDoc ''
        A directory to read sensitive configuration (secrets) from.

        Following secrets files are used by default:
        - `${lib.strings.removePrefix cfg.configDir envFile.generated.secrets}` - generated sensitive environment variables
        - `${lib.strings.removePrefix cfg.configDir envFile.user.secrets}` - user editable sensitive environment variables
      '';
    };

    jwtValiditySeconds = lib.mkOption {
      type = with lib.types; ints.u32;
      default = 24 * 60 * 60;
      description = lib.mdDoc ''
        Validity period of issued JWT authentication tokens in seconds;
      '';
    };

    cors.maxAge = lib.mkOption {
      type = with lib.types; int;
      default = 5 * 60;
      description = lib.mdDoc ''
        Maximum age of CORS preflight requests issued to Netmaker Server.

        see https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Access-Control-Max-Age
      '';
    };

    api.domain = lib.mkOption {
      type = with lib.types; str;
      default = "api.${cfg.domain}";
      description = lib.mdDoc ''
        The domain Netmaker Server's API is exposed on.
      '';
    };

    api.internal = lib.mkOption {
      type = lib.types.submodule ({ config, ... }: {
        options = {
          host = lib.mkOption {
            type = with lib.types; str;
            description = lib.mdDoc ''
              The host Netmaker Server's API is listening on internally.
            '';
          };
          port = lib.mkOption {
            type = lib.types.port;
            description = lib.mdDoc ''
              The port Netmaker Server's API is listening on internally.
            '';
          };
          addr = lib.mkOption {
            type = with lib.types; str;
            internal = true;
            readOnly = true;
            default = "${config.host}:${builtins.toString config.port}";
          };
        };
      });
      default = {
        host = cfg.internalListenAddress;
        port = 8081;
      };
      description = lib.mdDoc ''
        Specification of internally reachable listener for Netmaker Server's API.
      '';
    };

    ui.enable = lib.mkOption {
      type = with lib.types; bool;
      default = true;
      description = lib.mdDoc ''
        Should Netmaker (web) UI/Dashboard be enabled?
        According to official documentation Netmaker is usable without an UI through CLI tools.
      '';
    };
    ui.domain = lib.mkOption {
      type = with lib.types; str;
      default = "dashboard.${cfg.domain}";
      description = lib.mdDoc ''
        The domain Netmaker UI is exposed on.
      '';
    };
    ui.package = lib.mkOption {
      type = with lib.types; package;
      default = pkgs.kdn.netmaker-ui;
      description = lib.mdDoc ''
        The package to use for Netmaker UI
      '';
    };
    ui.saas.amuiUrl = lib.mkOption {
      type = with lib.types; str;
      default = "https://account.staging.netmaker.io";
      description = lib.mdDoc ''
        A piece configuration related to SaaS build of the UI.
      '';
    };
    ui.saas.intercomAppID = lib.mkOption {
      type = with lib.types; str;
      default = "";
      description = lib.mdDoc ''
        A piece configuration related to SaaS build of the UI.
      '';
    };

    firewall.ports = {
      networks.start = lib.mkOption {
        type = with lib.types; port;
        internal = true;
        readOnly = true;
        default = 51821;
      };
      networks.capacity = lib.mkOption {
        type = with lib.types; port;
        default = 10;

        description = lib.mdDoc ''
          Number of Netmaker networks to open up firewall for:
          > Netmaker needs one port per network, starting with 51821,
          > so open up a range depending on the number of networks
          > you plan on having. For instance, 51821-51830.
        '';
      };
    };

    webserver.type = lib.mkOption {
      type = with lib.types; enum [
        "caddy"
        "none"
      ];
      default = "caddy";
      description = lib.mdDoc ''
        A webserver to expose Netmaker Server components through:
        - Netmaker API
        - Netmaker UI
        - MQTT broker via websocket

        The module currently supports only Caddy or nothing at all (configured externally).
      '';
    };
    webserver.debug = lib.mkOption {
      type = with lib.types; bool;
      default = cfg.debug;
      description = lib.mdDoc ''
        Run webserver in a full debug mode.
      '';
    };

    db.type = lib.mkOption {
      type = with lib.types; enum [
        "sqlite"
        "rqlite"
        "postgres"
      ];
      default = "sqlite";
      description = lib.mdDoc ''
        Type of database to use for Netmaker.
        Only `sqlite` is supported without additional configuration.

        See [the source code](https://github.com/gravitl/netmaker/blob/fa9372ea56ef6e194dd57bf987bd86ac6d37e30f/database/database.go#L94-L105)
        for list of backends supported.
      '';
    };

    coredns.internal.port = lib.mkOption {
      type = lib.types.port;
      internal = true;
      readOnly = true;
      default = 53;
    };

    mqtt.type = lib.mkOption {
      type = with lib.types; enum [
        "mosquitto"
        "emqx"
      ];
      default = "mosquitto";
      description = lib.mdDoc ''
        Type of message queue to use for Netmaker.

        `emqx` [is not packaged in nixpkgs yet](https://github.com/NixOS/nixpkgs/issues/266659), therefore requires
        configuring external service yourself.
      '';
    };
    mqtt.internal = lib.mkOption {
      type = lib.types.submodule ({ config, ... }: {
        options = {
          host = lib.mkOption {
            type = with lib.types; str;
            description = lib.mdDoc ''
              The host message queue is listening on internally.
            '';
          };
          port = lib.mkOption {
            type = lib.types.port;
            description = lib.mdDoc ''
              The port message queue is listening on internally.
            '';
          };
          addr = lib.mkOption {
            type = with lib.types; str;
            internal = true;
            readOnly = true;
            default = "${config.host}:${builtins.toString config.port}";
          };
        };
      });
      default = {
        host = cfg.internalListenAddress;
        port = 9001;
      };
      description = lib.mdDoc ''
        Specification of internally reachable listener for the message queue.
      '';
    };
    mqtt.domain = lib.mkOption {
      type = with lib.types; str;
      default = "broker.${cfg.domain}";
      description = lib.mdDoc ''
        Domain the message queue is proxied through for external access.
      '';
    };
    mqtt.username = lib.mkOption {
      type = with lib.types; str;
      default = "netmaker";
      description = lib.mdDoc ''
        Username credential for the message queue.
      '';
    };
    mqtt.passwordFile = lib.mkOption {
      type = with lib.types; path;
      default = "${cfg.secretsDir}/MQ_PASSWORD";
      description = lib.mdDoc ''
        Location of the file holding password for the message queue (auto-generated by init script).
      '';
    };
    mqtt.acl.restricted = lib.mkEnableOption "restricting access to MQTT instance";
    mqtt.debug = lib.mkOption {
      type = with lib.types; bool;
      default = cfg.debug;
      description = lib.mdDoc ''
        Run message queue in a full debug mode.
      '';
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      environment.systemPackages = [ cfg.package ];

      networking.firewall.allowedUDPPortRanges = with cfg.firewall.ports;  [{
        from = networks.start;
        to = networks.start + networks.capacity - 1;
      }];
    }
    {
      systemd.tmpfiles.rules = [
        "d ${cfg.secretsDir} 1700 root root"
        "f ${envFile.generated.config} 1644 root root"
        "f ${envFile.generated.secrets} 1600 root root"
        "f ${envFile.user.config} 1644 root root"
        "f ${envFile.user.secrets} 1600 root root"
      ];

      services.netmaker.environmentFiles = [
        envFile.generated.config
        envFile.generated.secrets
        envFile.user.config
        envFile.user.secrets
        (lib.mkAfter cfg.environment)
      ];

      services.netmaker.config = {
        server.apiconn = "${cfg.api.domain}:443";
        server.apihost = cfg.api.domain;
        server.apilistenaddress = cfg.api.internal.host;
        server.apiport = builtins.toString cfg.api.internal.port;
        server.broker = "wss://${cfg.mqtt.domain}";
        server.brokertype = cfg.mqtt.type;
        server.database = cfg.db.type;
        server.frontendurl = "https://${cfg.ui.domain}";
        server.jwt_validity_seconds = cfg.jwtValiditySeconds;
        server.mqusername = cfg.mqtt.username;
        server.server = cfg.domain;
        server.serverbrokerendpoint = "ws://${cfg.mqtt.internal.addr}";
        server.telemetry = if cfg.telemetry then "on" else "off";
        server.verbosity = cfg.verbosity;
        # don't set to anything, see https://github.com/nazarewk/netmaker/blob/9ca6b44228847d246dd5617b73f69ec26778f396/servercfg/serverconf.go#L215-L223
        server.corednsaddr = "";
      };

      systemd.services.netmaker-configure = {
        serviceConfig.Type = "oneshot";
        serviceConfig.RemainAfterExit = true;
        script = lib.getExe (pkgs.writeShellApplication {
          name = "netmaker-generate-config";
          runtimeInputs = with pkgs; [
            coreutils
            gawk
            gnugrep
            gnused
          ];
          text = ''
            COREFILE="${cfg.dataDir}/config/dnsconfig/Corefile"
            MQ_PASSWORD_FILE="${cfg.mqtt.passwordFile}"

            SECRETS="${envFile.generated.secrets}"
            ENV="${envFile.generated.config}"

            ${builtins.readFile ./netmaker-generate-config.sh}
          '';
        });
      };

      # based on https://github.com/gravitl/netclient/blob/b9ea9c9841f01297955b03c2b5bbf4b5139aa40c/daemon/systemd_linux.go#L14-L30
      systemd.services.netmaker = {
        description = "Netmaker Server daemon";
        after = [ "network-online.target" "netmaker-configure.service" ];
        wants = [ "network-online.target" ];
        requires = [ "netmaker-configure.service" ];
        wantedBy = [ "multi-user.target" ];

        serviceConfig.EnvironmentFile = cfg.environmentFiles;
        serviceConfig.WorkingDirectory = cfg.dataDir;
        serviceConfig.ExecStart = "${lib.getExe cfg.package} -c ${cfg.config}";
        serviceConfig.ExecStartPost = pkgs.writeShellScript "configure-nmctl" ''
          export HOME=/root
          ${cfg.package}/bin/nmctl context set default \
            --endpoint="https://${cfg.api.domain}" \
            --master_key="$MASTER_KEY"
        '';

        serviceConfig.Restart = "on-failure";
        serviceConfig.RestartSec = "15s";
      };
    }
    {
      # CoreDNS related config
      services.coredns.enable = true;
      services.coredns.extraArgs = [
        "-conf=${cfg.dataDir}/config/dnsconfig/Corefile"
      ];
      networking.firewall = with cfg.firewall.ports; {
        allowedTCPPorts = [ cfg.coredns.internal.port ];
        allowedUDPPorts = [ cfg.coredns.internal.port ];
      };
    }
    (lib.mkIf (cfg.debugTools) {
      environment.systemPackages = with pkgs; [
        mqttui
        (pkgs.writeShellApplication {
          name = "netmaker-mqttui";
          runtimeInputs = with pkgs; [ mqttui jq ];
          text = ''
            get() {
              test -n "''${info:-}" || info="$(nmctl server info -o json | jq -c)"
              jq -r "$@" <<<"$info"
            }

            export MQTTUI_PASSWORD="''${MQTTUI_PASSWORD:-"$(get '.MQPassword')"}"
            export MQTTUI_USERNAME="''${MQTTUI_USERNAME:-"$(get '.MQUserName')"}"
            export MQTTUI_BROKER="''${MQTTUI_BROKER:-"$(get '.Broker')"}"
            exec mqttui "$@"
          '';
        })
      ];
    })
    (lib.mkIf (cfg.webserver.type == "caddy") {
      kdn.services.caddy.enable = true;
      systemd.services.netmaker.after = [ "caddy.service" ];
      systemd.services.netmaker.requires = [ "caddy.service" ];

      services.caddy.virtualHosts."https://${cfg.api.domain}".extraConfig = ''
        ${lib.optionalString (cfg.email != "") "tls ${cfg.email}"}
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
        ${lib.optionalString (cfg.email != "") "tls ${cfg.email}"}
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
          window.NMUI_AMUI_URL='${cfg.ui.saas.amuiUrl}';
          window.NMUI_INTERCOM_APP_ID='${cfg.ui.saas.intercomAppID}';
          window.NMUI_BACKEND_URL='https://${cfg.api.domain}';
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
    (lib.mkIf (cfg.mqtt.type == "mosquitto" && cfg.webserver.type == "caddy") {
      # see https://www.reddit.com/r/selfhosted/comments/14wqwa4/comment/jrp07gq/?utm_source=share&utm_medium=web3x&utm_name=web3xcss&utm_term=1&utm_content=share_button
      services.caddy.virtualHosts."https://${cfg.mqtt.domain}".extraConfig = ''
        ${lib.optionalString (cfg.email != "") "tls ${cfg.email}"}
        reverse_proxy http://${cfg.mqtt.internal.addr} {
          stream_timeout 6h
          stream_close_delay 1m
        }
      '';
    })
    (lib.mkIf (cfg.mqtt.type == "mosquitto") {
      systemd.services.mosquitto.after = [ "netmaker-configure.service" ];
      systemd.services.mosquitto.requires = [ "netmaker-configure.service" ];
      systemd.services.netmaker.after = [ "mosquitto.service" ];
      systemd.services.netmaker.requires = [ "mosquitto.service" ];

      services.mosquitto.enable = true;
      services.mosquitto.listeners = [{
        address = cfg.mqtt.internal.host;
        port = cfg.mqtt.internal.port;
        users."${cfg.mqtt.username}" = {
          passwordFile = cfg.mqtt.passwordFile;
          acl =
            if !cfg.mqtt.acl.restricted then [
              "readwrite #"
            ] else [
              # search for `client.Subscribe` in:
              # - https://github.com/gravitl/netmaker
              # - https://github.com/gravitl/netclient
              # https://github.com/gravitl/netclient
              "readwrite peers/host/+/+"
              "readwrite host/update/+/+"
              "readwrite node/update/+/+"
              # https://github.com/gravitl/netmaker
              "readwrite update/+/#"
              "readwrite host/serverupdate/+/#"
              "readwrite signal/+/#"
              "readwrite metrics/+/#"
            ];
        };
        settings.allow_anonymous = false;
        settings.protocol = "websockets";
      }];
    })
    (lib.mkIf (cfg.mqtt.type == "mosquitto" && cfg.mqtt.debug) {
      services.mosquitto.logType = [ "all" ];
    })
    (lib.mkIf (cfg.webserver.type == "caddy" && cfg.webserver.debug) {
      services.caddy.logFormat = "level DEBUG";
    })
  ]);
}
