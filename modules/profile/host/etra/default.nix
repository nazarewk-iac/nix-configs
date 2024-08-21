{ config, pkgs, lib, modulesPath, self, ... }:
let
  cfg = config.kdn.profile.host.etra;

  rCfg = config.kdn.networking.router;
  netconf = config.kdn.security.secrets.placeholders.networking;

  ula = {
    network = "fd12:ed4e:366d::";
    netmask = "48";
    pic = {
      network = "fd12:ed4e:366d:2::";
      netmask = "64";
      address.gateway = "fd12:ed4e:366d:2::1";
    };
    lan = {
      network = "fd12:ed4e:366d:1::";
      netmask = "64";
      address.gateway = "fd12:ed4e:366d:1::1";
    };
  };
  net.ipv4.pic = {
    network = "10.92.0.0";
    netmask = "16";
    address.gateway = "10.92.0.1";
  };
  net.ipv4.p2p.drek-etra = {
    network = "192.168.40.0";
    netmask = "31";
    address.gateway = "192.168.40.0";
    address.client = "192.168.40.1";
  };
  ll.drek.br-etra = "fe80::c641:1eff:fef8:9ce7"; # drek's link-local address
  vlan.pic.name = "pic";
  vlan.pic.id = 1859;
in
{
  options.kdn.profile.host.etra = {
    enable = lib.mkEnableOption "etra host profile";
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    # TODO: setup the dedicated YubiKey with GPG
    # TODO: setup the dedicated YubiKey with FIDO2 authentication
    {
      # 32GB RAM total
      kdn.profile.machine.baseline.enable = true;
      kdn.profile.machine.baseline.initrd.emergency.rebootTimeout = 30;
      kdn.hardware.cpu.intel.enable = true;
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
    (
      let
        cfg = config.kdn.hardware.disks;
        name = "emmc-etra";
        luksVol = cfg.luks.volumes."${name}";
      in
      {
        kdn.hardware.disks.initrd.failureTarget = "emergency.target";
        kdn.hardware.disks.enable = true;
        kdn.hardware.disks.devices."boot".path = "/dev/disk/by-id/usb-Lexar_USB_Flash_Drive_04R5Q5DX7R12U7QB-0:0";
        kdn.hardware.disks.luks.volumes."${name}" = {
          targetSpec.path = "/dev/disk/by-id/mmc-SCA128_0x061748d6";
          uuid = "696c5033-c9e8-4ce5-be8c-c9fe17566d2e";
          headerSpec.num = 2;
        };
      }
    )
    {
      systemd.network.networks."00-wan" = {
        /* cannot use IPv4 link-local addressing because it causes degraded state, see:
            - https://github.com/systemd/systemd/issues/575
            - https://github.com/systemd/systemd/issues/9077
         */
        addresses = [
          {
            Address = "192.168.40.1/31";
            Peer = "192.168.40.0/31";
          }
        ];
        networkConfig = {
          DNS = [
            net.ipv4.p2p.drek-etra.address.gateway
            ll.drek.br-etra
          ];
          Gateway = [
            net.ipv4.p2p.drek-etra.address.gateway
            ll.drek.br-etra
          ];
        };
      };
      networking.nameservers = lib.mkForce [ ];
      kdn.networking.router = {
        enable = true;
        debug = false;
        wan.type = "static";

        lan.address = [
          (with netconf.ipv4.network.etra.lan; "${address.gateway}/${netmask}")
          (with ula.lan; "${address.gateway}/${netmask}")
        ];
        lan.prefix = [
          (with netconf.ipv6.network.etra.lan; "${network}/${netmask}")
          (with ula.lan; "${network}/${netmask}")
        ];
        /* TODO: backup connection through NanoKVM? it could theoretically route the traffic?
            it is meant for maintenance access to NanoKVM itself, but maybe iptables could configure forwarding to WAN?
            see https://wiki.sipeed.com/hardware/en/kvm/NanoKVM/system/updating.html#Check-via-USB-RNDIS-Network-Interface
            see https://wiki.sipeed.com/hardware/en/kvm/NanoKVM/user_guide.html#RNDIS
        */
        #interfaces."enp0s20f0u3".role = "wan";
        #interfaces."enp0s20f0u3".matchConfig.Model = "licheervnano";
        interfaces."enp1s0".role = "wan-primary";
        #interfaces."enp2s0".role = "lan";
        interfaces."enp3s0".role = "lan";
      };
    }
    (
      let
        tpl.net = netconf.ipv6.network.etra.pic;
      in
      {
        kdn.networking.router.forwardings = [
          { from = vlan.pic.name; to = "wan"; }
        ];
        systemd.network.networks."00-lan" = {
          networkConfig.VLAN = [ vlan.pic.name ];
        };
        systemd.network.netdevs."00-${vlan.pic.name}" = {
          netdevConfig = {
            Name = vlan.pic.name;
            Kind = "vlan";
          };
          vlanConfig = {
            Id = vlan.pic.id;
          };
        };
        systemd.network.networks."00-${vlan.pic.name}" = {
          matchConfig = {
            Name = vlan.pic.name;
          };
          address = [
            (with net.ipv4.pic; "${address.gateway}/${netmask}")
            (with ula.pic; "${address.gateway}/${netmask}")
          ];
          addresses = [
            (with ula.pic; {
              Address = "${address.gateway}/${netmask}";
            })
          ];
          networkConfig = {
            Description = "'pic' Talos/Kubernetes cluster VLAN";
            DHCP = false;
            DHCPServer = true;
            IPMasquerade = "ipv4";
            # for DHCPv6-PD to work I would need to have `IPv6AcceptRA=true` on `wan`
            DHCPPrefixDelegation = false;
            IPv6AcceptRA = false;
            IPv6SendRA = true;
            IPv6PrivacyExtensions = true;
            IPv6LinkLocalAddressGenerationMode = "stable-privacy";
            MulticastDNS = true;
          };
          ipv6Prefixes = [
            (with ula.pic; {
              Prefix = "${network}/${netmask}";
              AddressAutoconfiguration = true;
              OnLink = true;
              Assign = false;
            })
          ];
        };
        sops.templates =
          let path = "/etc/systemd/network/00-pic.network.d/${rCfg.dropin.prefix}-static.conf"; in
          {
            "${path}" = {
              inherit path;
              mode = "0644";
              content = ''
                [Network]
                Address=${tpl.net.address.gateway}/${tpl.net.netmask}

                [IPv6Prefix]
                Prefix=${tpl.net.network}/${tpl.net.netmask}
                AddressAutoconfiguration=true
                OnLink=true
                Assign=false
              '';
            };
          };
      }
    )
  ]);
}
