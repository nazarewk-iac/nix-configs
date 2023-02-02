{ lib, pkgs, config, ... }:
let
  cfg = config.kdn.profile.machine.baseline;
in
{
  options.kdn.profile.machine.baseline = {
    enable = lib.mkEnableOption "enable baseline machine profile";
  };

  imports = [
    ../../../../machines/wireguard-peers.nix
  ];

  config = lib.mkIf cfg.enable {
    kdn.enable = true;
    kdn.profile.user.me.enable = true;

    # (modulesPath + "/installer/scan/not-detected.nix")
    hardware.enableRedistributableFirmware = true;

    networking.nameservers = [
      "2606:4700:4700::1111" # CloudFlare
      "1.1.1.1" # CloudFlare
      "8.8.8.8" # Google
    ];
    networking.networkmanager.enable = true;

    # REMOTE access
    services.openssh.enable = true;
    services.openssh.openFirewall = true;
    services.openssh.settings.PasswordAuthentication = false;
    kdn.programs.gnupg.enable = true;
    kdn.programs.gnupg.pass-secret-service.enable = true;

    # LOCALE
    i18n.defaultLocale = "en_US.UTF-8";
    i18n.extraLocaleSettings = {
      LC_TIME = "en_GB.UTF-8"; # en_GB - Monday as first day of week
    };
    time.timeZone = "Europe/Warsaw";
    location.provider = "geoclue2";

    # USERS
    users.users.root.initialHashedPassword = "";

    services.avahi.enable = true;

    environment.systemPackages = with pkgs; [
      cachix
    ];

    environment.shellAliases = {
      userctl = "systemctl --user";
      userjournal = "journalctl --user";

      sc = "systemctl";
      sj = "journalctl";

      uc = "systemctl --user";
      uj = "journalctl --user";

      scs = "systemctl status";
      ucs = "systemctl --user status";

      scmr = "systemctl restart";
      ucmr = "systemctl --user restart";

      scms = "systemctl start";
      ucms = "systemctl --user start";

      scmS = "systemctl stop";
      ucmS = "systemctl --user stop";
    };

    kdn.headless.base.enable = true;

    services.locate.enable = true;
    services.locate.localuser = null;
    services.locate.locate = pkgs.mlocate;
    services.locate.pruneBindMounts = true;

    kdn.networking.wireguard.enable = true;
    kdn.hardware.disk-encryption.tools.enable = true;
    kdn.hardware.usbip.enable = true;
    kdn.hardware.qmk.enable = true;
    kdn.development.shell.enable = true;

    home-manager.users.root = { kdn.profile.user.me.nixosConfig = config.users.users.root; };

    boot.kernelParams = [
      # blank screen after 90 sec
      "consoleblank=90"
    ];

    # see https://nixos.wiki/wiki/Full_Disk_Encryption#Option_2:_Copy_Key_as_file_onto_a_vfat_usb_stick
    # see https://bbs.archlinux.org/viewtopic.php?pid=329790#p329790
    boot.initrd.availableKernelModules = [
      "ahci"
      "nls_cp437" # fixes unknown codepages when mounting vfat
      "nls_iso8859_1" # fixes unknown codepages when mounting vfat
      "nls_iso8859_2" # fixes unknown codepages when mounting vfat
      "nvme" # NVMe disk
      "sd_mod" # SCSI disk support
      "uas" # USB Attached SCSI disks (eg. Samsung T5)
      "usb_storage" # usb disks
      "usbcore"
      "usbhid"
      "vfat" # mount vfat-formatted boot partition
      "xhci_hcd" # usb disks
      "xhci_pci"
    ];

    kdn.networking.netbird.instances.priv = 51821;
  };
}
