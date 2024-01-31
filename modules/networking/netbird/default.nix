{ lib
, pkgs
, config
, ...
}:
let
  cfg = config.kdn.networking.netbird;

  instancesList = builtins.attrValues cfg.instances;

  mkWrappers = instance:
    let
      vars = lib.trivial.pipe instance.envVars [
        (lib.mapAttrsToList lib.strings.toShellVar)
        (lib.strings.concatStringsSep " ")
      ];
      mkBinary = tool: pkgs.writeScriptBin "${tool}-${instance.alias}" ''
        #!${lib.getExe pkgs.bash}
        export ${vars}
        ${lib.getExe' config.services.netbird.package tool} "$@"
      '';
    in
    builtins.map mkBinary [ "netbird" "netbird-mgmt" "netbird-signal" ];
in
{
  options.kdn.networking.netbird = {
    instances = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule ({ config, name, ... }: {
        options = {
          alias = lib.mkOption {
            type = with lib.types; str;
            readOnly = true;
            default = name;
          };
          name = lib.mkOption {
            type = with lib.types; str;
            readOnly = true;
            default = "netbird-${config.alias}";
          };
          port = lib.mkOption {
            type = lib.types.port;
            description = lib.mdDoc ''
              The port Netbird's wireguard interface will listen on.
            '';
          };
          logLevel = lib.mkOption {
            type = with lib.types; enum [
              # logrus loglevels
              "panic"
              "fatal"
              "error"
              "warn"
              "warning"
              "info"
              "debug"
              "trace"
            ];
            default = "info";
          };
          workDir = lib.mkOption {
            type = with lib.types; str;
            readOnly = true;
            default = "/var/lib/${config.name}";
          };
          envVars = lib.mkOption {
            type = with lib.types; attrsOf str;
            default = { };
            apply = new: {
              NB_LOG_FILE = "console";
              NB_LOG_LEVEL = config.logLevel;
              NB_CONFIG = "/var/lib/${config.name}/config.json";
              NB_DAEMON_ADDR = "unix:///var/run/${config.name}/sock";
              NB_INTERFACE_NAME = "wt-${config.alias}";
              NB_WIREGUARD_PORT = builtins.toString config.port;
            } // new;
          };
        };
      }));
      default = { };
    };

  };

  config = lib.mkMerge [
    {
      services.netbird.package = pkgs.kdn.netbird;
    }
    (lib.mkIf (cfg.instances != { }) {
      environment.systemPackages = lib.lists.flatten (builtins.map mkWrappers instancesList);

      boot.extraModulePackages = lib.optional (lib.versionOlder config.boot.kernelPackages.kernel.version "5.6") config.boot.kernelPackages.wireguard;

      # ignore wt* interfaces
      networking.dhcpcd.denyInterfaces = [ "wt*" ];
      networking.networkmanager.unmanaged = [ "interface-name:wt*" ];
      systemd.network.networks."50-netbird-instantiated" = lib.mkIf config.networking.useNetworkd {
        matchConfig = {
          Name = lib.mkForce "wt*";
        };
        linkConfig = {
          Unmanaged = true;
          ActivationPolicy = "manual";
        };
      };

      systemd.services = lib.trivial.pipe instancesList [
        (builtins.map (instance: {
          name = instance.name;
          value = {
            description = "A WireGuard-based mesh network that connects your devices into a single private network";
            documentation = [ "https://netbird.io/docs/" ];
            after = [ "network.target" ];
            wantedBy = [ "multi-user.target" ];
            path = lib.optional (!config.services.resolved.enable) pkgs.openresolv;
            environment = instance.envVars;
            serviceConfig = {
              Restart = "always";
              ExecStart =
                let
                  binary = lib.getExe' config.services.netbird.package "netbird";
                in
                "${binary} service run";

              # User/Group names for DynamicUser
              User = instance.name;
              Group = instance.name;
              # Restrict permissinos
              DynamicUser = true;
              RuntimeDirectory = instance.name;
              StateDirectory = instance.name;
              StateDirectoryMode = "0700";
              WorkingDirectory = instance.workDir;

              AmbientCapabilities =
                let kernelVersion = config.boot.kernelPackages.kernel.version;
                in [
                  # see https://man7.org/linux/man-pages/man7/capabilities.7.html
                  # see https://docs.netbird.io/how-to/installation#running-net-bird-in-docker
                  # seems to work fine without CAP_SYS_ADMIN and CAP_SYS_RESOURCE
                  # CAP_NET_BIND_SERVICE could be added to allow binding on low ports, but is not required, see https://github.com/netbirdio/netbird/pull/1513

                  # failed creating tunnel interface wt-priv: [operation not permitted
                  "CAP_NET_ADMIN"
                  # failed to pull up wgInterface [wt-priv]: failed to create ipv4 raw socket: socket: operation not permitted
                  "CAP_NET_RAW"
                ]
                # required for eBPF filter, used to be subset of CAP_SYS_ADMIN
                ++ lib.optional (lib.versionAtLeast kernelVersion "5.8") "CAP_BPF"
                ++ lib.optional (lib.versionOlder kernelVersion "5.8") "CAP_SYS_ADMIN"
              ;
            };
            unitConfig = {
              StartLimitInterval = 5;
              StartLimitBurst = 10;
            };
            stopIfChanged = false;
          };
        }))
        builtins.listToAttrs
      ];

      networking.firewall.allowedUDPPorts = builtins.map (instance: instance.port) instancesList;

      # see https://github.com/systemd/systemd/blob/17f3e91e8107b2b29fe25755651b230bbc81a514/src/resolve/org.freedesktop.resolve1.policy#L43-L43
      security.polkit.extraConfig = lib.mkIf config.services.resolved.enable (
        let
          isAllowedUser = lib.pipe instancesList [
            (builtins.map (instance: ''subject.user == ${builtins.toJSON instance.name}''))
            (builtins.concatStringsSep " || ")
            (v: "( ${v} )")
          ];
        in
        ''
          // systemd-resolved access for Netbird
          polkit.addRule(function(action, subject) {
            if ( action.id.indexOf("org.freedesktop.resolve1.") == 0 && ${isAllowedUser} ) {
              return polkit.Result.YES;
            }
          });
        ''
      );
    })
  ];
}
