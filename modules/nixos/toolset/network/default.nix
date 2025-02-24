{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.toolset.network;
in {
  options.kdn.toolset.network = {
    enable = lib.mkEnableOption "networking tooling";
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      programs.wireshark.enable = true;
      kdn.services.iperf3.enable = true;

      environment.systemPackages = with pkgs; [
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
        iptables
        nftables
      ];
    }
    (lib.mkIf config.kdn.desktop.enable {
      environment.systemPackages = with pkgs; [
        wireshark
      ];
    })
  ]);
}
