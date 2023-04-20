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

  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      kdn.enable = true;
      kdn.profile.user.me.enable = true;

      # (modulesPath + "/installer/scan/not-detected.nix")
      hardware.enableRedistributableFirmware = true;

      # systemd-boot
      boot.initrd.systemd.emergencyAccess = "$y$j9T$fioAEKxXi2LmH.9HyzVJ4/$Ot4PUjYdz7ELvJBOnS1YgQFNW89SCxB/yyGVaq4Aux0";
      boot.loader.efi.canTouchEfiVariables = true;
      boot.loader.systemd-boot.enable = true;
      boot.loader.systemd-boot.configurationLimit = 10;
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
      kdn.programs.gnupg.enable = true;
      kdn.programs.gnupg.pass-secret-service.enable = true;

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
    })
    (lib.mkIf config.boot.initrd.systemd.enable {
      specialisation.boot-debug = {
        inheritParentConfig = true;
        configuration = lib.mkMerge [
          {
            system.nixos.tags = [ "boot-debug" ];
            boot.kernelParams = [
              # see https://www.thegeekdiary.com/how-to-debug-systemd-boot-process-in-centos-rhel-7-and-8-2/
              #"systemd.confirm_spawn=true"  # this seems to ask and times out before executing anything during boot
              "systemd.debug-shell=1"
              "systemd.log_level=debug"
              "systemd.unit=multi-user.target"
            ];
          }
        ];
      };
    })
  ];
}
