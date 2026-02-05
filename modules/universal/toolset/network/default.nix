{
  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}: let
  cfg = config.kdn.toolset.network;
in {
  options.kdn.toolset.network = {
    enable = lib.mkEnableOption "networking tooling";
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      kdn.env.packages = with pkgs; [
        (lib.meta.setPrio 10 nettools)
        (lib.meta.setPrio 20 inetutils) # telnet etc.
        socat
        arp-scan
        bind # provides: dnssec-*, named-*, ...
        dnsutils # another output of `pkgs.bind`, provides: dig, delv, nslookup, nsupdate
        nmap
        bandwhich
        tcpdump
        wol
        iperf
        speedtest-go
        speedtest-cli
        ssh-tools
        (lib.hiPrio wireshark-cli)
      ];
    }
    (lib.mkIf config.kdn.desktop.enable {
      kdn.env.packages = with pkgs; [
        (lib.lowPrio wireshark-qt) # aka wireshark-qt
      ];
    })
    (kdnConfig.util.ifTypes ["nixos"] {
      programs.wireshark.enable = true;
      kdn.services.iperf3.enable = true;
      kdn.env.packages = with pkgs; [
        conntrack-tools
        ebtables
        iptables
        nftables
      ];
    })
  ]);
}
