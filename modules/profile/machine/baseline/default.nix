{ lib, pkgs, config, self, ... }:
let
  cfg = config.kdn.profile.machine.baseline;
in
{
  options.kdn.profile.machine.baseline = {
    enable = lib.mkEnableOption "baseline machine profile for server/non-interactive use";

    initrd.emergency.rebootTimeout = lib.mkOption {
      type = lib.types.ints.unsigned;
      default = 0;
    };

  };

  imports = [
    ../../../../data/wireguard-peers.nix
  ];

  config = lib.mkIf cfg.enable (lib.mkMerge [
    (lib.mkIf config.disko.enableConfig {
      # WARNING: without depending on `config.disko.enableConfig` it fails on machines without dedicated `/boot` partition
      fileSystems."/boot".options = [ "fmask=0077" "dmask=0077" ];
    })
    {
      kdn.enable = true;
      kdn.profile.user.kdn.enable = true;

      # systemd.sysusers.enable = true; # systemd-sysusers doesn't create normal users. You can currently only use it to create system users.

      # (modulesPath + "/installer/scan/not-detected.nix")
      hardware.enableRedistributableFirmware = true;

      # systemd-boot
      boot.initrd.systemd.emergencyAccess = "$y$j9T$fioAEKxXi2LmH.9HyzVJ4/$Ot4PUjYdz7ELvJBOnS1YgQFNW89SCxB/yyGVaq4Aux0";
      boot.initrd.systemd.enable = true;
      boot.loader.efi.canTouchEfiVariables = true;
      boot.loader.systemd-boot.configurationLimit = 10;
      boot.loader.systemd-boot.enable = true;

      boot.tmp.cleanOnBoot = lib.mkDefault (!config.boot.tmp.useTmpfs);
      boot.tmp.useTmpfs = lib.mkDefault true;
      boot.tmp.tmpfsSize = lib.mkDefault "10%";

      boot.initrd.systemd.users.root.shell = lib.getExe pkgs.bashInteractive;
      boot.initrd.systemd.storePaths = with pkgs; [
        (lib.getExe bashInteractive)
      ];
      boot.initrd.systemd.initrdBin = with pkgs; [
        gnugrep
        gnused
        coreutils
        findutils
        moreutils
        which
      ];

      # prefer appending NetworkManager nameservers when it is available
      networking.networkmanager.appendNameservers = [
        #"2606:4700:4700::1111" # CloudFlare
        #"1.1.1.1" # CloudFlare
        #"8.8.8.8" # Google
      ];
      # otherwise fallback to inserting non-networkmanager servers
      networking.nameservers = lib.mkIf
        (!config.networking.networkmanager.enable)
        (with config.networking.networkmanager; insertNameservers ++ appendNameservers);

      networking.networkmanager.enable = lib.mkDefault true;
      networking.networkmanager.logLevel = lib.mkDefault "INFO";

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
        jq
        sshfs
        kdn.systemd-find-cycles
        (pkgs.writeShellApplication {
          name = "kdn-systemd-find-cycles";
          runtimeInputs = with pkgs; [ kdn.systemd-find-cycles systemd ];
          text = ''
            # see https://github.com/systemd/systemd/issues/3829#issuecomment-327773498
            systemd_args=()
            dot_args=()
            reading_dot=1
            for arg in "$@"; do
              if test "$arg" == "--" ; then
                test "$reading_dot" == 0 && reading_dot=1 || reading_dot=0
              elif test "$reading_dot" == 1 ; then
                dot_args+=("$arg")
              else
                systemd_args+=("$arg")
              fi
            done
            systemd-analyze dot --no-pager --order "''${systemd_args[@]}" | systemd-find-cycles "''${dot_args[@]}"
          '';
        })
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

      services.resolved.enable = true;
      # services.resolved.dnssec = "allow-downgrade"; # this complains results are not signed
      services.resolved.dnssec = lib.mkDefault "false";
      services.resolved.dnsovertls = lib.mkDefault "opportunistic";
      services.resolved.llmnr = "true";
      services.resolved.extraConfig = ''
        MulticastDNS=true
      '';
      services.avahi.enable = false; # conficts with `resolved` `MulticastDNS`/`LLMNR`

      kdn.development.shell.enable = true;
      kdn.filesystems.zfs.enable = true;
      kdn.hardware.usbip.enable = true;
      kdn.hardware.yubikey.enable = true;
      kdn.networking.wireguard.enable = true;
      kdn.programs.direnv.enable = true;

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

      services.devmon.enable = false; # disable auto-mounting service devmon, it interferes with disko
      # TODO: download and/or symlink sources that the system got built from?
    }
    {
      kdn.networking.dynamic-hosts.enable = true;
      sops.templates = lib.pipe config.kdn.security.secrets.placeholders.networking.hosts [
        (lib.attrsets.mapAttrsToList (name: text:
          let path = "/etc/hosts.d/60-${config.kdn.managed.infix.default}-${name}.hosts"; in {
            "${path}" = {
              inherit path;
              mode = "0644";
              content = text;
            };
          }))
        lib.mkMerge
      ];
    }
    {
      systemd.tmpfiles.rules = lib.trivial.pipe config.users.users [
        lib.attrsets.attrValues
        (builtins.filter (u: u.isNormalUser))
        (builtins.map (user:
          let
            h = user.home;
            u = builtins.toString (user.uid or user.name);
            g = builtins.toString (user.gid or user.group);
          in
          [
            # fix home directory permissions
            "d ${h} 0750 ${u} ${g} - -"
            # fix user profile directory permissions
            "d /nix/var/nix/profiles/per-user/${user.name} 0755 ${u} ${g} - -"
          ]
        ))
        builtins.concatLists
      ];
    }
    {
      # fix all /home mountpoints permissions
      systemd.tmpfiles.rules =
        let
          users = lib.pipe config.users.users [
            lib.attrsets.attrValues
            (builtins.filter (u: u.isNormalUser))
          ];
        in
        lib.trivial.pipe config.fileSystems [
          (lib.attrsets.mapAttrsToList (name: cfg: cfg.mountPoint or name))
          (builtins.map (mountpoint: lib.trivial.pipe users [
            (builtins.filter (user:
              (lib.strings.hasPrefix user.home mountpoint)
              && (user.home != mountpoint)
            ))
            (builtins.map (user:
              let
                h = user.home;
                u = builtins.toString (user.uid or user.name);
                g = builtins.toString (user.gid or user.group);
              in
              lib.pipe mountpoint [
                (lib.strings.removePrefix "${h}/")
                (lib.strings.splitString "/")
                (pcs: builtins.map (i: lib.lists.sublist 0 i pcs) (lib.lists.range 1 (builtins.length pcs)))
                (builtins.map (lib.strings.concatStringsSep "/"))
                (builtins.map (path: "d ${h}/${path} 0750 ${u} ${g} - -"))
              ]
            ))
          ]))
          lib.lists.flatten
          lib.lists.unique
        ];
    }
    (
      # TODO: test it
      # reboot if dropped into emergency and left unattended
      let timeout = cfg.initrd.emergency.rebootTimeout; in lib.mkIf (timeout > 0) {
        boot.initrd.systemd.services."emergency" = {
          overrideStrategy = "asDropin";
          postStart = ''
            if ! /bin/systemd-ask-password --timeout=${builtins.toString timeout} \
              --no-output --emoji=no \
              "Are you there? Press enter to enter emergency shell."
            then
              /bin/systemctl reboot
            fi
          '';
        };
      }
    )
    {
      home-manager.sharedModules = [{
        kdn.development.git.enable = true;
      }];
    }
    {
      # TODO: checkout the repository while installing?
      systemd.tmpfiles.rules = [
        "L /etc/nixos/flake.nix       - - - - flake.nix.rel"
        "L /etc/nixos/flake.nix.rel   - - - - /home/kdn/dev/github.com/nazarewk-iac/nix-configs/flake.nix"
        "L /etc/nixos/flake.nix.abs   - - - - ../../home/kdn/dev/github.com/nazarewk-iac/nix-configs/flake.nix"
      ];
    }
    {
      kdn.networking.netbird.priv.enable = true;
      services.netbird.package = pkgs.netbird.overrideAttrs (old: {
        patches = old.patches or [ ] ++ [
          #(pkgs.fetchpatch {
          #  url = "https://github.com/netbirdio/netbird/pull/2026/commits/3f2eff10772aeda98799110cfceaf6712fc9690a.patch";
          #  name = "route-read-envs.patch";
          #  hash = "sha256-0Up0ongOvgCxEX2fKznd1ZVcJ6ars3i0j8e3bx978xw=";
          #})
        ];
      });
    }
    {
      kdn.services.nextcloud-client-nixos.enable = config.kdn.security.secrets.allowed;
    }
    {
      kdn.security.secrets.enable = lib.mkDefault true;
      kdn.security.secrets.files."default" = {
        sopsFile = "${self}/default.unattended.sops.yaml";
      };
      kdn.security.secrets.files."networking" = {
        keyPrefix = "networking";
        sopsFile = "${self}/default.unattended.sops.yaml";
        basePath = "/run/configs";
        sops.mode = "0444";
      };
      system.activationScripts.setupSecrets.text = lib.mkDefault "true";
      system.activationScripts.kdnSopsNixFixupSecretsPermissions = {
        deps = [ "setupSecrets" ];
        text = ''
          chmod -R go+r /run/configs
        '';
      };
      environment.systemPackages = with pkgs; [
        (pkgs.writers.writePython3Bin "kdn-net-anonymize" { } (builtins.readFile ./kdn-net-anonymize.py))
      ];
    }
    (
      let
        anonymize = (pkgs.writers.writePython3Bin "kdn-net-anonymize" { } (builtins.readFile ./kdn-net-anonymize.py));
        anonymizeClipboard = pkgs.writeShellApplication {
          name = "kdn-net-anonymize-clipboard";
          runtimeInputs = with pkgs; [
            anonymize
            wl-clipboard
            libnotify
          ];
          text = ''
            tempdir="$(mktemp /tmp/kdn-net-anonymize-clipboard.XXXXXX)"
            trap 'rm -rf "$tempdir" || :' EXIT
            wl-paste | kdn-net-anonymize 2>"$tempdir" | wl-copy
            notify-send --expire-time=3000 "kdn-net-anonymize-clipboard" "$(cat "$tempdir")"
          '';
        };
      in
      {
        environment.systemPackages = [ anonymize ]
          ++ lib.lists.optional config.kdn.headless.enableGUI anonymizeClipboard
        ;
        home-manager.sharedModules = [{
          wayland.windowManager.sway = {
            config.keybindings = with config.kdn.desktop.sway.keys; {
              "${ctrl}+${super}+A" = "exec '${lib.getExe anonymizeClipboard}'";
            };
          };
        }];
      }
    )
  ]);
}
