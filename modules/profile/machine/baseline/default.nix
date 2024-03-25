{ lib, pkgs, config, ... }:
let
  cfg = config.kdn.profile.machine.baseline;
in
{
  options.kdn.profile.machine.baseline = {
    enable = lib.mkEnableOption "baseline machine profile for server/non-interactive use";
  };

  imports = [
    ../../../../data/wireguard-peers.nix
  ];

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      kdn.enable = true;
      kdn.profile.user.kdn.enable = true;

      # (modulesPath + "/installer/scan/not-detected.nix")
      hardware.enableRedistributableFirmware = true;

      # systemd-boot
      boot.initrd.systemd.emergencyAccess = "$y$j9T$fioAEKxXi2LmH.9HyzVJ4/$Ot4PUjYdz7ELvJBOnS1YgQFNW89SCxB/yyGVaq4Aux0";
      boot.initrd.systemd.enable = true;
      boot.loader.efi.canTouchEfiVariables = true;
      boot.loader.systemd-boot.configurationLimit = 10;
      boot.loader.systemd-boot.enable = true;
      boot.tmp.cleanOnBoot = true;

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

      location.provider = "geoclue2";

      # USERS
      users.mutableUsers = false;
      # conflicts with <nixos/modules/profiles/installation-device.nix>
      users.users.root.initialHashedPassword = lib.mkForce "$y$j9T$AhbnpYZawNWNGfuq1h9/p0$jmitwtZwTr72nBgvg2TEmrGmhRR30sQ.hQ7NZk1NqJD";

      environment.systemPackages = with pkgs; [
        dracut # for lsinitrd
      ];

      environment.shellAliases =
        let
          commands = n: prefix: {
            "${n}" = prefix;
            "${n}c" = "${prefix} cat";
            "${n}r" = "${prefix} restart";
            "${n}s" = "${prefix} status";
            "${n}uS" = "${prefix} stop";
            "${n}us" = "${prefix} start";
            "${n}ur" = "${prefix} restart";
          };
        in
        {
          sj = "journalctl";
          uj = "journalctl --user";
        } // (commands "sc" "systemctl") // (commands "uc" "systemctl --user");

      kdn.headless.base.enable = true;

      services.locate.enable = true;
      services.locate.localuser = null;
      services.locate.package = pkgs.mlocate;
      services.locate.pruneBindMounts = true;

      services.avahi.enable = false; # conficts with `services.resolved.llmnr`
      services.resolved.enable = true;
      services.resolved.llmnr = "true";
      kdn.networking.wireguard.enable = true;
      kdn.hardware.disk-encryption.tools.enable = true;
      kdn.hardware.usbip.enable = true;
      kdn.development.shell.enable = true;

      home-manager.users.root = { kdn.profile.user.kdn.osConfig = config.users.users.root; };

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

      services.netbird.clients.priv.port = 51819;

      services.devmon.enable = false; # disable auto-mounting service devmon, it interferes with disko

      system.activationScripts.users-mountpoints.text =
        let
          users = lib.pipe config.users.users [
            lib.attrsets.attrValues
            (builtins.filter (u: u.isNormalUser))
          ];
        in
        lib.trivial.pipe config.fileSystems [
          (lib.attrsets.mapAttrsToList (name: cfg: cfg.mountPoint or name))
          (builtins.map (mountpoint: lib.trivial.pipe users [
            (builtins.map (user: lib.lists.optional
              (lib.strings.hasPrefix user.home mountpoint)
              ''chown ${builtins.toString (user.uid or user.name)}:users "${mountpoint}"''
            ))
          ]))
          lib.lists.flatten
          (builtins.concatStringsSep "\n")
        ];
    }
  ]);
}
