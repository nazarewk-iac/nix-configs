{
  lib,
  pkgs,
  config,
  kdn,
  ...
}: let
  inherit (kdn) self;
  cfg = config.kdn.profile.machine.baseline;
in {
  options.kdn.profile.machine.baseline = {
    initrd.emergency.rebootTimeout = lib.mkOption {
      type = lib.types.ints.unsigned;
      default = 0;
    };
  };

  imports = [
    ./remote-builders.nix
  ];

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {home-manager.sharedModules = [{kdn.profile.machine.baseline.enable = true;}];}
      (lib.mkIf config.disko.enableConfig {
        # WARNING: without depending on `config.disko.enableConfig` it fails on machines without dedicated `/boot` partition
        fileSystems."/boot".options = [
          "fmask=0077"
          "dmask=0077"
        ];
      })
      (
        let
          content = let
            gen = pkgs.writers.writePython3Bin "generate-subuid" {} ''
              import os

              with open(os.environ["out"], "w") as f:
                  for uid in range(1000, 65536):
                      f.write(f"{uid}:{uid * 65536}:{65536}\n")
            '';
          in
            pkgs.runCommand "etc-subuid-subgid" {} (lib.getExe gen);
        in {
          # WARNING: with userborn, `/etc/sub{u,g}id` is not managed anymore
          services.userborn.enable = true;
          # with userborn, /etc/passwd & group is dynamically generated and will differ between reboots unless persisted
          services.userborn.passwordFilesLocation = "/var/lib/nixos/userborn/etc";

          environment.etc."subuid".source = content;
          environment.etc."subuid".mode = "0444";
          environment.etc."subgid".source = content;
          environment.etc."subgid".mode = "0444";
        }
      )
      {
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
      }
      {
        networking.nftables.enable = true; # iptables is just a compatibility layer
        # prefer appending NetworkManager nameservers when it is available
        networking.networkmanager.appendNameservers = [
          #"2606:4700:4700::1111" # CloudFlare
          #"1.1.1.1" # CloudFlare
          #"8.8.8.8" # Google
        ];
        # otherwise fallback to inserting non-networkmanager servers
        networking.nameservers = lib.mkIf (!config.networking.networkmanager.enable) (
          with config.networking.networkmanager; insertNameservers ++ appendNameservers
        );

        networking.networkmanager.enable = lib.mkDefault true;
        networking.networkmanager.logLevel = lib.mkDefault "INFO";

        # `UseDomains = true` for adding search domain `route` for just DNS queries
        systemd.network.config.networkConfig.UseDomains = lib.mkDefault true;
      }
      {
        # REMOTE access
        services.openssh.enable = true;
        services.openssh.openFirewall = true;
        services.openssh.settings.PasswordAuthentication = false;
        services.openssh.settings.GatewayPorts = "clientspecified";
        programs.ssh.extraConfig = lib.mkBefore ''
          Include /etc/ssh/ssh_config.d/*.config
        '';

        location.provider = "geoclue2";

        # USERS
        users.mutableUsers = false;
        # conflicts with <nixos/modules/profiles/installation-device.nix>
        users.users.root.initialHashedPassword = lib.mkForce "$y$j9T$AhbnpYZawNWNGfuq1h9/p0$jmitwtZwTr72nBgvg2TEmrGmhRR30sQ.hQ7NZk1NqJD";

        environment.systemPackages = with pkgs; [
          dracut # for lsinitrd
          jq
          sshfs
          pkgs.kdn.systemd-find-cycles
          (pkgs.writeShellApplication {
            name = "kdn-systemd-find-cycles";
            runtimeInputs = with pkgs; [
              pkgs.kdn.systemd-find-cycles
              systemd
            ];
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

        environment.shellAliases = let
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
          }
          // (commands "sc" "systemctl")
          // (commands "uc" "systemctl --user");

        kdn.headless.base.enable = true;

        services.locate.enable = true;
        services.locate.package = pkgs.mlocate;
        services.locate.pruneBindMounts = true;

        kdn.networking.resolved.enable = true;
        services.avahi.enable = false; # conficts with `resolved` `MulticastDNS`/`LLMNR`

        kdn.development.shell.enable = lib.mkDefault true;
        kdn.fs.zfs.enable = lib.mkDefault true;
        kdn.hw.usbip.enable = lib.mkDefault true;
        kdn.hw.yubikey.enable = lib.mkDefault true;
        kdn.programs.direnv.enable = lib.mkDefault true;
        kdn.security.disk-encryption.enable = lib.mkDefault true;

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
      (lib.mkIf config.kdn.security.secrets.allowed {
        kdn.networking.dynamic-hosts.enable = true;
        sops.templates = lib.pipe config.kdn.security.secrets.sops.placeholders.networking.hosts [
          (lib.attrsets.mapAttrsToList (
            name: text: let
              path = "/etc/hosts.d/60-${config.kdn.managed.infix.default}-${name}.hosts";
            in {
              "${path}" = {
                inherit path;
                mode = "0644";
                content = text;
              };
            }
          ))
          (
            l:
              l
              ++ [
                {
                  # TODO: render those from "$XDG_CONFIG_DIRS/nix/access-tokens.d/*.tokens" for both users and system-wide?
                  "nix.access-tokens.auto.conf" = {
                    path = "/etc/nix/nix.access-tokens.auto.conf";
                    mode = "0444";
                    content = lib.pipe config.kdn.security.secrets.sops.placeholders.default.nix.access-tokens [
                      (lib.attrsets.mapAttrsToList (name: value: "${name}=${value}"))
                      (builtins.concatStringsSep " ")
                      (value: ''
                        access-tokens = ${value}
                      '')
                    ];
                  };
                }
              ]
          )
          lib.mkMerge
        ];
      })
      {
        environment.etc."ssh/ssh_config.d/00-kdn-profile-baseline.config".text = ''
          Match User nixos
            StrictHostKeyChecking no
            UpdateHostKeys no
            UserKnownHostsFile /dev/null
        '';
      }
      {
        # ~/dev/github.com/nazarewk-iac/nix-configs/known_hosts.sh
        programs.ssh.knownHostsFiles = [./ssh_known_hosts];
      }
      {
        systemd.tmpfiles.rules = lib.trivial.pipe config.users.users [
          lib.attrsets.attrValues
          (builtins.filter (u: u.isNormalUser))
          (builtins.map (
            user: let
              h = user.home;
              u = builtins.toString (user.uid or user.name);
              g = builtins.toString (user.gid or user.group);
            in [
              # fix user profile directory permissions
              "d /nix/var/nix/profiles/per-user/${user.name} 0750 ${u} ${g} - -"
            ]
          ))
          builtins.concatLists
        ];
      }
      (
        # TODO: test it
        # reboot if dropped into emergency and left unattended
        let
          timeout = cfg.initrd.emergency.rebootTimeout;
        in
          lib.mkIf (timeout > 0) {
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
        home-manager.sharedModules = [{kdn.development.git.enable = true;}];
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
        # interferes with Netbird networking
        kdn.networking.tailscale.enable = false;
      }
      {
        kdn.networking.netbird.default.enable = false;
        # don't let unvetted clients arbitrary config to the system
        kdn.networking.netbird.default.environment.NB_DISABLE_DNS = "true";
        kdn.networking.netbird.default.environment.NB_BLOCK_INBOUND = "true";

        kdn.networking.netbird.clients.priv.idx = 1; # private account
        kdn.networking.netbird.clients.priv.enable = true;
        kdn.networking.netbird.clients.priv.environment.NB_DISABLE_DNS = "false";
        kdn.networking.netbird.clients.priv.environment.NB_BLOCK_INBOUND = "false";

        kdn.networking.netbird.clients.nbs.idx = 2; # internal NetBird instance
        # TODO: this doesn't work (doesn't set up routes)
        kdn.networking.netbird.clients.nbs.systemd.enable = false;
        # TODO: this doesn't work
        kdn.networking.netbird.clients.nbs.resolvesDomains = ["~netbird.selfhosted"];
        kdn.networking.netbird.clients.nbt.idx = 3; # testing client
        kdn.networking.netbird.clients.nbc.idx = 4; # cloud client
        kdn.networking.netbird.clients.t1.idx = 5; # testing client
        kdn.networking.netbird.clients.t2.idx = 6; # testing client
        kdn.networking.netbird.clients.t3.idx = 7; # testing client
      }
      {
        kdn.services.nextcloud-client-nixos.enable = config.kdn.security.secrets.allowed;
      }
      {
        kdn.security.secrets.enable = lib.mkDefault true;
        kdn.security.secrets.sops.files."default" = {
          sopsFile = "${self}/default.unattended.sops.yaml";
        };
        kdn.security.secrets.sops.files."networking" = {
          keyPrefix = "networking";
          sopsFile = "${self}/default.unattended.sops.yaml";
          basePath = "/run/configs";
          sops.mode = "0444";
        };

        environment.systemPackages = with pkgs; [
          (pkgs.writeShellApplication {
            name = "kdn-net-anonymize";
            text = ''
              ${lib.getExe pkgs.kdn.kdn-anonymize} /run/configs/networking/anonymization
            '';
          })
        ];
      }
      (lib.mkIf config.kdn.security.secrets.allowed {
        systemd.services.sops-install-secrets.postStart = ''
          chmod -R go+r /run/configs
        '';
      })
      (
        let
          anonymizeClipboard = pkgs.writeShellApplication {
            name = "kdn-anonymize-clipboard";
            runtimeInputs = with pkgs; [
              pkgs.kdn.kdn-anonymize
              wl-clipboard
              libnotify
            ];
            text = ''
              # see https://github.com/bugaevc/wl-clipboard/issues/245
              notify-send --expire-time=3000 "kdn-anonymize-clipboard" "$( { wl-paste | kdn-anonymize | wl-copy 2>/dev/null ; } 2>&1 )"
            '';
          };
        in {
          kdn.security.secrets.sops.files."anonymization" = {
            keyPrefix = "anonymization";
            sopsFile = "${self}/default.unattended.sops.yaml";
            basePath = "/run/configs";
            sops.mode = "0444";
          };

          environment.sessionVariables.KDN_ANONYMIZE_DEFAULTS = "/run/configs";
          environment.systemPackages =
            [
              pkgs.kdn.kdn-anonymize
            ]
            ++ lib.lists.optional config.kdn.desktop.enable anonymizeClipboard;
          home-manager.sharedModules = [
            {
              wayland.windowManager.sway = {
                config.keybindings = with config.kdn.desktop.sway.keys; {
                  "${ctrl}+${super}+A" = "exec '${lib.getExe anonymizeClipboard}'";
                };
              };
            }
          ];
        }
      )
    ]
  );
}
