{ config, pkgs, lib, modulesPath, self, ... }:
let
  cfg = config.kdn.profile.host.etra;
  hostname = config.networking.hostName;
in
{
  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      networking.useDHCP = false;
      networking.networkmanager.enable = false;
      systemd.network.enable = true;

      # https://gist.github.com/mweinelt/b78f7046145dbaeab4e42bf55663ef44
      # Enable forwarding between all interfaces, restrictions between
      # individual links are enforced by firewalling.
      boot.kernel.sysctl = {
        "net.ipv6.conf.all.forwarding" = 1;
        "net.ipv4.ip_forward" = 1;
      };

      # When true, systemd-networkd will remove routes that are not configured in .network files
      systemd.network.config.networkConfig.ManageForeignRoutes = false;
    }
    {
      # WAN
      systemd.network.netdevs."10-wan-bond" = {
        # see https://wiki.archlinux.org/title/Systemd-networkd#Bonding_a_wired_and_wireless_interface
        netdevConfig.Kind = "bond";
        netdevConfig.Name = "wan";
        bondConfig.Mode = "active-backup";
        bondConfig.PrimaryReselectPolicy = "always";
        bondConfig.MIIMonitorSec = "1s";
      };
      systemd.network.networks."10-enp1s0-wan" = {
        matchConfig.Name = "enp1s0";
        networkConfig.Bond = "wan";
        networkConfig.PrimarySlave = true;
      };
      systemd.network.networks."10-wan" = {
        matchConfig.Name = "wan";
        networkConfig.BindCarrier = [ "enp1s0" ];
        linkConfig.RequiredForOnline = "routable";
        networkConfig.DHCP = "ipv4";
        networkConfig.IPv6AcceptRA = true;
      };
    }
  ]);
}
