{ lib
, pkgs
, config
, ...
}:
let
  cfg = config.kdn.networking.netbird;

  cmd = "${config.services.netbird.package}/bin/netbird";
  mkEnvVars = alias: port: {
    NB_CONFIG = "/var/lib/netbird-${alias}/config.json";
    NB_DAEMON_ADDR = "unix:///var/run/netbird-${alias}/sock";
    NB_WG_IFACE = "wt-${alias}";
    NB_WG_PORT = builtins.toString port;
  };
in
{
  options.kdn.networking.netbird = {
    instances = lib.mkOption {
      type = lib.types.attrsOf lib.types.ints.unsigned;
      default = { };
    };
  };

  config = lib.mkMerge [
    { services.netbird.package = pkgs.kdn.netbird; }
    (lib.mkIf (cfg.instances != { }) {

      environment.systemPackages = [ config.services.netbird.package ];

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

      systemd.services = lib.trivial.pipe cfg.instances [
        (builtins.mapAttrs (alias: port: {
          name = "netbird-${alias}";
          value = {
            description = "A WireGuard-based mesh network that connects your devices into a single private network";
            documentation = [ "https://netbird.io/docs/" ];
            after = [ "network.target" ];
            wantedBy = [ "multi-user.target" ];
            environment = {
              NB_LOG_FILE = "console";
            } // (mkEnvVars alias port);
            serviceConfig = {
              AmbientCapabilities = [ "CAP_NET_ADMIN" ];
              DynamicUser = true;
              ExecStart = "${cmd} service run";
              Restart = "always";
              RuntimeDirectory = "netbird-${alias}";
              StateDirectory = "netbird-${alias}";
              StateDirectoryMode = "0700";
              WorkingDirectory = "/var/lib/netbird-${alias}";
            };
            unitConfig = {
              StartLimitInterval = 5;
              StartLimitBurst = 10;
            };
            stopIfChanged = false;
          };
        }))
        builtins.attrValues
        builtins.listToAttrs
      ];

      environment.shellAliases = lib.trivial.pipe cfg.instances [
        (builtins.mapAttrs (alias: port:
          let
            vars = lib.trivial.pipe (mkEnvVars alias port) [
              (lib.mapAttrsToList lib.strings.toShellVar)
              (lib.strings.concatStringsSep " ")
            ];
          in
          {
            "netbird-${alias}" = "${vars} ${cmd}";
          }))
        builtins.attrValues
        (lib.lists.foldl (a: b: a // b) { })
      ];
    }
    )
  ];
}
