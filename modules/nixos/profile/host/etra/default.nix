{
  config,
  pkgs,
  lib,
  kdn,
  ...
}: let
  inherit (kdn) self;
  cfg = config.kdn.profile.host.etra;

  rCfg = config.kdn.networking.router;
  netconf = config.kdn.security.secrets.sops.placeholders.networking;

  ula = {
    network = "fd12:ed4e:366d::";
    netmask = "48";
    lan = {
      network = "fd12:ed4e:366d:1c07::";
      netmask = "64";
      address.gateway = "fd12:ed4e:366d:1c07:cdda:c7b8:2a69:4d47";
    };
    pic = {
      network = "fd12:ed4e:366d:eb17::";
      netmask = "64";
      address.gateway = "fd12:ed4e:366d:eb17:b2c4:dde2:269a:6dd9";
    };
  };
  net.ipv4.p2p.drek-etra = {
    network = "192.168.40.0";
    netmask = "31";
    address.gateway = "192.168.40.0";
    address.client = "192.168.40.1";
  };
  ll.drek.br-etra = "fe80::c641:1eff:fef8:9ce7";
  ll.etra.br-etra = "fe80::b47b:911a:2d95:d12f";
  vlan.pic.name = "pic";
  vlan.pic.id = 1859;

  hosts.pic.pwet.macs.enp2s0 = "a8:b8:e0:04:10:b5";
  hosts.pic.pwet.macs.enp3s0 = "a8:b8:e0:04:10:b6";
  hosts.pic.pwet.macs.enp4s0 = "a8:b8:e0:04:10:b7";
  hosts.pic.pwet.macs.enp5s0 = "a8:b8:e0:04:10:b8";

  hosts.pic.turo.macs.enp2s0 = "a8:b8:e0:04:13:0d";
  hosts.pic.turo.macs.enp3s0 = "a8:b8:e0:04:13:0e";
  hosts.pic.turo.macs.enp4s0 = "a8:b8:e0:04:13:0f";
  hosts.pic.turo.macs.enp5s0 = "a8:b8:e0:04:13:10";

  hosts.pic.yost.macs.enp2s0 = "a8:b8:e0:04:12:f1";
  hosts.pic.yost.macs.enp3s0 = "a8:b8:e0:04:12:f2";
  hosts.pic.yost.macs.enp4s0 = "a8:b8:e0:04:12:f3";
  hosts.pic.yost.macs.enp5s0 = "a8:b8:e0:04:12:f4";

  hosts.lan.anji.ifaces.default.mac = "2c:82:17:da:21:24";
  hosts.lan.cafal.ifaces.default.ipv4 = "192.168.73.2";
  hosts.lan.cafal.ifaces.default.mac = "00:23:79:00:31:03";
  hosts.lan.etra.ifaces.default.ipv4 = "192.168.73.1";
  hosts.lan.faro.ifaces.default.mac = "3e:e7:84:fb:f0:94";
  hosts.lan.feren.ifaces.default.ipv4 = "192.168.73.3";
  hosts.lan.feren.ifaces.default.mac = "00:23:79:00:23:11";
  hosts.lan.moak.ifaces.default.ipv4 = "192.168.73.4";
  hosts.lan.moak.ifaces.default.mac = "00:23:79:00:31:2F";
  hosts.lan.pryll.ifaces.default.mac = "01:90:1b:0e:84:8c:f7";
  hosts.lan.anji-vm-macos-01.default.mac = "f6:f2:45:7a:32:79";
in {
  options.kdn.profile.host.etra = {
    enable = lib.mkEnableOption "etra host profile";
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      # TODO: setup the dedicated YubiKey with GPG
      # TODO: setup the dedicated YubiKey with FIDO2 authentication
      {
        # 32GB RAM total
        kdn.profile.machine.baseline.enable = true;
        kdn.profile.machine.baseline.initrd.emergency.rebootTimeout = 30;
        kdn.hw.cpu.intel.enable = true;
        security.sudo.wheelNeedsPassword = false;

        zramSwap.enable = lib.mkDefault true;
        zramSwap.memoryPercent = 50;
        zramSwap.priority = 100;

        boot.tmp.tmpfsSize = "8G";
        boot.initrd.kernelModules = [
          "sdhci"
          "sdhci_pci"
        ];
      }
      {
        kdn.hw.disks.initrd.failureTarget = "rescue.target";
        kdn.hw.disks.enable = true;
        kdn.hw.disks.devices."boot".path = "/dev/disk/by-id/usb-Lexar_USB_Flash_Drive_04R5Q5DX7R12U7QB-0:0";

        #kdn.hw.disks.luks.volumes."emmc-etra" = {
        #  targetSpec.path = "/dev/disk/by-id/mmc-SCA128_0x061748d6";
        #  uuid = "696c5033-c9e8-4ce5-be8c-c9fe17566d2e";
        #  headerSpec.num = 2;
        #};
        kdn.hw.disks.luks.volumes."980pro-etra" = {
          targetSpec.path = "/dev/disk/by-id/nvme-eui.002538b841a03e40";
          uuid = "9fbfa860-9833-4bde-8cb1-1e80e1e59a65";
          headerSpec.num = 3;
        };
      }
      {
        kdn.networking.router.enable = true;
        # seems to spam logs too much
        networking.firewall.logRefusedConnections = false;
      }
      {
        systemd.network.wait-online.extraArgs = [
          "--interface=wan"
        ];
        kdn.networking.router.nets.wan = {
          type = "wan";
          netdev.kind = "bond";
          interfaces = ["enp1s0"];
          address = [];
          wan.asDefaultDNS = true;
          wan.dns = [
            net.ipv4.p2p.drek-etra.address.gateway
            ll.drek.br-etra
          ];
          wan.gateway = [
            net.ipv4.p2p.drek-etra.address.gateway
            ll.drek.br-etra
          ];
          template.network.sections.p2p-drek-etra.Address = with net.ipv4.p2p.drek-etra; {
            /*
             cannot use IPv4 link-local addressing because it causes degraded state, see:
            - https://github.com/systemd/systemd/issues/575
            - https://github.com/systemd/systemd/issues/9077
            */
            Address = "${address.client}/${netmask}";
            Peer = "${address.gateway}/${netmask}";
          };
        };
        kdn.networking.router.kresd.upstreams = [
          {
            description = "lan.drek.net.int.kdn.im";
            type = "STUB";
            nameservers = [net.ipv4.p2p.drek-etra.address.gateway];
            domains = ["lan.drek.net.int.kdn.im."];
          }
        ];
      }
      {
        kdn.networking.router.nets."lan".addressing."ipv4".hosts =
          lib.pipe
          [
            # first batch
            "a5:8b"
            "e4:52"
            "fa:56"
            "4e:6e"
            "43:85"
            # second batch
            "42:94"
            "05:0c"
            "27:95"
            "92:97"
            "26:e2"
          ]
          [
            (builtins.map lib.strings.toLower)
            (builtins.map (
              macSuffix: let
                mac = "48:da:35:6f:${macSuffix}";
                suffix = builtins.replaceStrings [":"] [""] macSuffix;
              in {
                name = "kvm-${suffix}";
                value.ident.hw-address = mac;
              }
            ))
            builtins.listToAttrs
          ];
      }
      {
        kdn.networking.router.nets.lan = {
          type = "lan";
          lan.uplink = "wan";
          netdev.kind = "bond";
          netdev.bond.mode = "aggregate";
          interfaces = [
            "enp2s0"
            "enp3s0"
          ];
          address = [
            (with ula.lan; "${address.gateway}/${netmask}")
            (with netconf.ipv6.network.etra.lan; "${address.gateway}/${netmask}")
          ];
          addressing.ipv4 = {
            subnet-id = 3236353446;
            network = "192.168.73.0";
            netmask = "24";
            pools.default.start = "192.168.73.32";
            pools.default.end = "192.168.73.254";
            hosts = lib.pipe hosts.lan [
              # TODO: implement non-default interfaces
              (lib.attrsets.filterAttrs (name: h: h ? ifaces && h.ifaces ? default))
              (builtins.mapAttrs (
                name: h: let
                  iface = h.ifaces.default;
                in
                  lib.mkMerge [
                    (lib.mkIf (iface ? ipv4) {ip = iface.ipv4;})
                    (lib.mkIf (iface ? mac) {ident.hw-address = iface.mac;})
                  ]
              ))
            ];
          };
          addressing.ipv6-ula = with ula.lan; {
            subnet-id = 300310722;
            inherit network netmask;
            hosts.etra.ip = address.gateway;
          };
          addressing.ipv6-public = with netconf.ipv6.network.etra.lan; {
            subnet-id = 108555261;
            inherit network netmask;
            hosts.etra.ip = address.gateway;
          };
          prefix.ula = with ula.lan; "${network}/${netmask}";
          prefix.public = with netconf.ipv6.network.etra.lan; "${network}/${netmask}";
        };

        kdn.networking.router.nets.pic = {
          type = "lan";
          lan.uplink = "wan";
          netdev.kind = "vlan";
          vlan.id = vlan.pic.id;
          interfaces = ["lan"];
          address = [
            #(with ula.pic; "${address.gateway}/${netmask}")
            #(with netconf.ipv6.network.etra.pic; "${address.gateway}/${netmask}")
          ];
          prefix.ula = with ula.pic; "${network}/${netmask}";
          prefix.public = with netconf.ipv6.network.etra.pic; "${network}/${netmask}";

          addressing.ipv4 = {
            subnet-id = 2332818586;
            network = "10.92.0.0";
            netmask = "16";
            pools.default.start = "10.92.0.32";
            pools.default.end = "10.92.0.254";
            hosts.etra.ip = "10.92.0.1";
          };
          addressing.ipv6-local = with ula.pic; {
            subnet-id = 22449285;
            inherit network netmask;
            hosts.etra.ip = address.gateway;
            hosts.k8s.ip = "fd12:ed4e:366d:eb17:ad77:71d3:4170:ed6d";
          };
          addressing.ipv6-public = with netconf.ipv6.network.etra.pic; {
            subnet-id = 197717597;
            inherit network netmask;
            hosts.etra.ip = address.gateway;
          };
        };
      }
      {
        kdn.networking.router.nets.pic = let
          entries = lib.pipe hosts.pic [
            (builtins.mapAttrs (
              name: host: {
                idents =
                  lib.attrsets.mapAttrsToList (iface: mac: {
                    hw-address = mac;
                  })
                  host.macs;
              }
            ))
          ];
        in {
          addressing.ipv4.hosts = entries;
          addressing.ipv6-local.hosts = entries;
          addressing.ipv6-public.hosts = entries;
        };
      }
      {
        # accept all traffic coming from Netbird to any other routed network
        networking.firewall.trustedInterfaces = ["nb-priv"];
      }
      {
        kdn.networking.router.nets.wan = {
          firewall.allowedUDPPorts = [
            53
            853
          ];
        };
        kdn.networking.router.knot.listens = [
          net.ipv4.p2p.drek-etra.address.client
          "${ll.etra.br-etra}%wan"
        ];

        networking.firewall = {
          allowedTCPPorts = [
            53
            853
          ];
          allowedUDPPorts = [
            53
            853
          ];
        };
        kdn.networking.router.domains."int.kdn.im." = {};
        kdn.networking.router.dhcp-ddns.suffix = "net.int.kdn.im.";
        services.kresd.instances = 2;
      }
      {
        kdn.networking.router.addr.public.ipv4.path =
          config.sops.secrets."networking/ipv4/network/isp/uplink/address/client".path;
        kdn.networking.router.addr.public.ipv6.path =
          config.sops.secrets."networking/ipv6/network/isp/prefix/etra/address/gateway".path;
      }
      {
        kdn.networking.router.debug.ddns = true;
      }
      {
        kdn.hw.nanokvm.enable = true;
      }
      {
        kdn.security.secrets.sops.files."dns" = {
          sopsFile = "${self}/dns.sops.yaml";
        };
        kdn.networking.router.tsig.keyTpls =
          config.kdn.security.secrets.sops.placeholders.dns.knot-dns.keys;
      }
    ]
  );
}
