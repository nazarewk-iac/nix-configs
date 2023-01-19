{ lib
, pkgs
, config
, ...
}:
let
  cfg = config.kdn.networking.netbird;

  mkEnvVars = alias: port: {
    NB_CONFIG = "/var/lib/netbird/${alias}/config.json";
    NB_DAEMON_ADDR = "unix:///var/run/netbird/${alias}/sock";
    NB_WG_IFACE = "wt-${alias}";
  } // (lib.mkIf (port != 0) {
    NB_WG_PORT = lib.toString port;
  });
in
{
  options.kdn.networking.netbird = {
    enable = lib.mkEnableOption "Netbird VPN based on Wireguard";
    instances = lib.mkOption {
      type = lib.types.attrsOf lib.types.ints.unsigned;
      default = { };
    };
  };

  config = lib.mkMerge [
    (lib.mkIf (cfg.enable) {
      services.netbird.enable = true;
    })
    (lib.mkIf (cfg.enable || cfg.instances != { }) {
      services.netbird.package = pkgs.kdn.netbird;

      networking.networkmanager.unmanaged = [ "interface-name:wt*" ];

      environment.systemPackages = with pkgs; [
        kdn.netbird-ui
      ];
    })
    (lib.mkIf (cfg.instances != { }) ({
      # based on https://github.com/nazarewk/nixpkgs/blob/befc83905c965adfd33e5cae49acb0351f6e0404/nixos/modules/services/networking/netbird.nix
      boot.extraModulePackages = lib.optional (lib.versionOlder config.boot.kernelPackages.kernel.version "5.6") config.boot.kernelPackages.wireguard;

      environment.systemPackages = [ config.services.netbird.package ];

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

      systemd.services."netbird@" = {
        description = "A WireGuard-based mesh network that connects your devices into a single private network";
        documentation = [ "https://netbird.io/docs/" ];
        after = [ "network.target" ];
        wantedBy = [ "multi-user.target" ];
        environment = {
          NB_LOG_FILE = "console";
        } // (mkEnvVars "%i" 0);
        serviceConfig = {
          AmbientCapabilities = [ "CAP_NET_ADMIN" ];
          DynamicUser = true;
          ExecStart = "${config.services.netbird.package}/bin/netbird service run";
          Restart = "always";
          RuntimeDirectory = "netbird/%i";
          StateDirectory = "netbird/%i";
          WorkingDirectory = "/var/lib/netbird/%i";
        };
        unitConfig = {
          StartLimitInterval = 5;
          StartLimitBurst = 10;
        };
        stopIfChanged = false;
      };
    }))
    (builtins.mapAttrs
      # TODO: fix infinite recursion
      (alias: port:
        let
          envVars = mkEnvVars alias port;
          aliasVars = lib.strings.toShellVars envVars;
        in
        {
          systemd.services."netbird@${alias}".environment = envVars;
          environment.shellAliases = {
            "netbird-${alias}" = "${aliasVars} netbird";
            "netbird-ui-${alias}" = "${aliasVars} netbird-ui";
          };
        })
      cfg.instances)
  ];
}
