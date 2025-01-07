{
  lib,
  pkgs,
  config,
  self,
  ...
}: let
  cfg = config.kdn.hardware.nanokvm;
in {
  options.kdn.hardware.nanokvm = {
    enable = lib.mkEnableOption "NanoKVM setup";
    ethernet.autoConnect = lib.mkOption {
      type = with lib.types; bool;
      default = false;
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      # TODO: systemd-networkd version
      # Ethernet
      services.udev.extraRules = ''
        ACTION=="add", SUBSYSTEM=="net", ENV{ID_MODEL}=="licheervnano", ENV{ID_MODEL_ID}=="1009", ENV{ID_NET_DRIVER}=="rndis_host", ENV{NM_UNMANAGED}="1", NAME="usb-nanokvm"
      '';
      /*
      UDEV  [9346.588485] add      /devices/pci0000:00/0000:00:08.1/0000:10:00.3/usb5/5-3/5-3:1.0/net/enp16s0f3u3 (net)
      ACTION=add
      CURRENT_TAGS=:systemd:
      DEVPATH=/devices/pci0000:00/0000:00:08.1/0000:10:00.3/usb5/5-3/5-3:1.0/net/enp16s0f3u3
      ID_BUS=usb
      ID_MM_CANDIDATE=1
      ID_MODEL=licheervnano
      ID_MODEL_ENC=licheervnano
      ID_MODEL_ID=1009
      ID_NET_DRIVER=rndis_host
      ID_NET_LINK_FILE=/nix/store/xg6f0c5pchmc2jq84s4np19j1rnn90mn-systemd-256.6/lib/systemd/network/99-default.link
      ID_NET_NAME=enp16s0f3u3
      ID_NET_NAME_MAC=enx66644e76cdf3
      ID_NET_NAME_PATH=enp16s0f3u3
      ID_NET_NAMING_SCHEME=v255
      ID_PATH=pci-0000:10:00.3-usb-0:3:1.0
      ID_PATH_TAG=pci-0000_10_00_3-usb-0_3_1_0
      ID_PATH_WITH_USB_REVISION=pci-0000:10:00.3-usbv2-0:3:1.0
      ID_RENAMING=1
      ID_REVISION=0510
      ID_SERIAL=flyingrtx_licheervnano_0123456789ABCDEF
      ID_SERIAL_SHORT=0123456789ABCDEF
      ID_TYPE=generic
      ID_USB_DRIVER=rndis_host
      ID_USB_INTERFACES=:0202ff:0a0000:030001:030002:080650:
      ID_USB_INTERFACE_NUM=00
      ID_USB_MODEL=licheervnano
      ID_USB_MODEL_ENC=licheervnano
      ID_USB_MODEL_ID=1009
      ID_USB_REVISION=0510
      ID_USB_SERIAL=flyingrtx_licheervnano_0123456789ABCDEF
      ID_USB_SERIAL_SHORT=0123456789ABCDEF
      ID_USB_TYPE=generic
      ID_USB_VENDOR=flyingrtx
      ID_USB_VENDOR_ENC=flyingrtx
      ID_USB_VENDOR_ID=3346
      ID_VENDOR=flyingrtx
      ID_VENDOR_ENC=flyingrtx
      ID_VENDOR_ID=3346
      IFINDEX=96
      INTERFACE=enp16s0f3u3
      INTERFACE_OLD=usb0
      PATH=/nix/store/pj8r0y4kk8mz4igbnsy5gf8swid22ipz-udev-path/bin:/nix/store/pj8r0y4kk8mz4igbnsy5gf8swid22ipz-udev-path/sbin
      SEQNUM=14641
      SUBSYSTEM=net
      SYSTEMD_ALIAS=/sys/subsystem/net/devices/enp16s0f3u3
      TAGS=:systemd:
      UDEV_DATABASE_VERSION=1
      USEC_INITIALIZED=46453248
      */
      networking.networkmanager.ensureProfiles.profiles.nanokvm = {
        connection = {
          id = "usb-nanokvm";
          type = "ethernet";
          interface-name = "usb-nanokvm";
          autoconnect = cfg.ethernet.autoConnect;
          autoconnect-priority = -999;
        };
        ipv4.method = "auto";
        ipv6.method = "auto";
        ipv6.addr-gen-mode = "stable-privacy";
      };
    }
  ]);
}
