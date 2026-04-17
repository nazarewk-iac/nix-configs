{
  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}:
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

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      # home-manager
      (kdnConfig.util.ifHM (
        lib.mkMerge [
          {
            xdg.configFile."kdn/source-flake".source = kdnConfig.self;

            home.sessionPath = [ "$HOME/.local/bin" ];
            #systemd.user.tmpfiles.settings.kdn-bin.rules."%h/.local/bin".d = {};
            systemd.user.tmpfiles.rules = [
              "d %h/.local/bin - - - -"
            ];
          }
          {
            xdg.userDirs.enable = pkgs.stdenv.isLinux;
            xdg.userDirs.setSessionVariables = lib.mkDefault true; # 2025-03-23: default changed to false
            xdg.userDirs.createDirectories = false;
          }
          {
            kdn.disks.persist."usr/cache".directories = [
              ".cache/appimage-run" # not sure where exactly it comes from
            ]
            ++ lib.lists.optional config.fonts.fontconfig.enable ".cache/fontconfig";
            kdn.disks.persist."usr/state".files = [
              ".local/share/fish/fish_history" # A file already exists at ...
              ".ipython/profile_default/history.sqlite"
              ".bash_history"
              ".duckdb_history"
              ".python_history"
              ".usql_history"
              ".zsh_history"
            ];
          }
        ]
      ))
      # universal
      {
        kdn.enable = true;
        kdn.locale.enable = true;
        kdn.profile.user.kdn.enable = true;

        kdn.profile.remote-builders.enable = lib.mkDefault true;
        kdn.profile.default-secrets.enable = lib.mkDefault true;
      }
      {
        kdn.env.packages = with pkgs; [
          git
          bash
          curl
          jq
          sshfs

          nix-derivation # pretty-derivation
          nix-output-monitor
          nix-du
          nix-tree
          pkgs.kdn.kdn-nix

          # TODO: remove after resolving https://github.com/sfcompute/hardware_report/issues/22 ?
          (lib.mkIf (
            !pkgs.stdenv.hostPlatform.isDarwin
          ) kdnConfig.self.inputs.hardware-report.packages."${pkgs.stdenv.hostPlatform.system}".default)
        ];
      }
      # shared/darwin-nixos
      (kdnConfig.util.ifTypes [ "nixos" "darwin" ] {
        services.openssh.enable = true;
        environment.etc."kdn/source-flake".source = kdnConfig.self;
        nix.gc.automatic = true;
        services.angrr.enable = lib.mkDefault true;
        services.angrr.settings = {
          temporary-root-policies = {
            direnv = {
              path-regex = "/\\.direnv/";
              period = "7d";
            };
            result = {
              path-regex = "/result[^/]*$";
              period = "5d";
            };
          };
          profile-policies = {
            system = {
              profile-paths = [ "/nix/var/nix/profiles/system" ];
              keep-since = "14d";
              keep-latest-n = 5;
              keep-booted-system = true;
              keep-current-system = true;
            };
            user = {
              enable = false;
              profile-paths = [
                "~/.local/state/nix/profiles/profile"
                "/nix/var/nix/profiles/per-user/root/profile"
              ];
              keep-since = "1d";
              keep-latest-n = 1;
            };
          };
        };
      })
      (kdnConfig.util.ifTypes [ "nixos" ] {
        services.angrr.enableNixGcIntegration = true;
      })
      # darwin
      (kdnConfig.util.ifTypes [ "darwin" ] (
        lib.mkMerge [
          { home-manager.sharedModules = [ { kdn.profile.machine.baseline.enable = true; } ]; }
          (lib.mkIf config.kdn.security.secrets.allowed {
            system.activationScripts.postActivation.text = lib.mkOrder 1501 ''
              chmod -R go+r /run/configs
            '';
          })
        ]
      ))
      # nixos
      (kdnConfig.util.ifTypes [ "nixos" ] (
        lib.mkMerge [
          { home-manager.sharedModules = [ { kdn.profile.machine.baseline.enable = true; } ]; }
          (lib.mkIf (config.disko.enableConfig or false) {
            fileSystems."/boot".options = [
              "fmask=0077"
              "dmask=0077"
            ];
          })
          (
            let
              content =
                let
                  gen = pkgs.writers.writePython3Bin "generate-subuid" { } ''
                    import os

                    with open(os.environ["out"], "w") as f:
                        for uid in range(1000, 65536):
                            f.write(f"{uid}:{uid * 65536}:{65536}\n")
                  '';
                in
                pkgs.runCommand "etc-subuid-subgid" { } (lib.getExe gen);
            in
            {
              services.userborn.enable = true;
              services.userborn.passwordFilesLocation = "/var/lib/nixos/userborn/etc";
              environment.etc."subuid".source = content;
              environment.etc."subuid".mode = "0444";
              environment.etc."subgid".source = content;
              environment.etc."subgid".mode = "0444";
            }
          )
          {
            hardware.enableRedistributableFirmware = true;
            boot.initrd.systemd.emergencyAccess = "$y$j9T$fioAEKxXi2LmH.9HyzVJ4/$Ot4PUjYdz7ELvJBOnS1YgQFNW89SCxB/yyGVaq4Aux0";
            boot.initrd.systemd.enable = lib.mkDefault true;
            boot.loader.efi.canTouchEfiVariables = lib.mkDefault true;
            boot.loader.systemd-boot.configurationLimit = 10;
            boot.loader.systemd-boot.enable = lib.mkDefault true;
            boot.tmp.cleanOnBoot = lib.mkDefault (!config.boot.tmp.useTmpfs);
            boot.tmp.useTmpfs = lib.mkDefault true;
            boot.tmp.tmpfsSize = lib.mkDefault "10%";
            boot.initrd.systemd.users.root.shell = lib.getExe pkgs.bashInteractive;
            boot.initrd.systemd.storePaths = with pkgs; [ (lib.getExe bashInteractive) ];
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
            networking.nftables.enable = true;
            networking.networkmanager.appendNameservers = [ ];
            networking.nameservers = lib.mkIf (!config.networking.networkmanager.enable) (
              with config.networking.networkmanager; insertNameservers ++ appendNameservers
            );
            networking.networkmanager.enable = lib.mkDefault true;
            networking.networkmanager.logLevel = lib.mkDefault "INFO";
            systemd.network.enable = lib.mkDefault true;
            networking.useNetworkd = lib.mkDefault true;
            systemd.network.wait-online.enable = lib.mkDefault (
              lib.attrsets.filterAttrs (
                _: net: !(net.linkConfig.Unmanaged or false) config.systemd.network.networks
              ) != { }
            );
            systemd.network.wait-online.anyInterface = lib.mkDefault true;
            systemd.network.config.networkConfig.UseDomains = lib.mkDefault true;
          }
          {
            services.openssh.enable = true;
            services.openssh.openFirewall = true;
            services.openssh.settings.PasswordAuthentication = lib.mkDefault false;
            services.openssh.settings.GatewayPorts = "clientspecified";
            programs.ssh.extraConfig = lib.mkBefore ''
              Include /etc/ssh/ssh_config.d/*.config
            '';
            location.provider = "geoclue2";
            users.mutableUsers = false;
            users.users.root.initialHashedPassword = lib.mkForce "$y$j9T$AhbnpYZawNWNGfuq1h9/p0$jmitwtZwTr72nBgvg2TEmrGmhRR30sQ.hQ7NZk1NqJD";
            kdn.env.packages = with pkgs; [
              dracut
              pkgs.kdn.systemd-find-cycles
              (pkgs.writeShellApplication {
                name = "kdn-systemd-find-cycles";
                runtimeInputs = with pkgs; [
                  pkgs.kdn.systemd-find-cycles
                  systemd
                ];
                text = ''
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
              }
              // (commands "sc" "systemctl")
              // (commands "uc" "systemctl --user");
            kdn.headless.base.enable = true;
            services.locate.enable = true;
            services.locate.package = pkgs.mlocate;
            services.locate.pruneBindMounts = true;
            kdn.networking.resolved.enable = lib.mkDefault true;
            services.avahi.enable = lib.mkDefault false;
            kdn.development.shell.enable = lib.mkDefault true;
            kdn.fs.zfs.enable = lib.mkDefault true;
            kdn.hw.usbip.enable = lib.mkDefault true;
            kdn.hw.yubikey.enable = lib.mkDefault true;
            kdn.programs.direnv.enable = lib.mkDefault true;
            kdn.security.disk-encryption.enable = lib.mkDefault true;
            boot.kernelParams = [ "consoleblank=90" ];
            boot.initrd.availableKernelModules = [
              "ahci"
              "nls_cp437"
              "nls_iso8859_1"
              "nls_iso8859_2"
              "nvme"
              "sd_mod"
              "uas"
              "usb_storage"
              "usbcore"
              "usbhid"
              "vfat"
              "xhci_hcd"
              "xhci_pci"
            ];
            services.devmon.enable = false;
            kdn.networking.dynamic-hosts.enable = true;
          }
          {
            environment.etc."ssh/ssh_config.d/00-kdn-profile-baseline.config".text = ''
              Match User nixos
                StrictHostKeyChecking no
                UpdateHostKeys no
                UserKnownHostsFile /dev/null
            '';
          }
          { programs.ssh.knownHostsFiles = [ ./ssh_known_hosts ]; }
          {
            systemd.tmpfiles.rules = lib.trivial.pipe config.users.users [
              lib.attrsets.attrValues
              (builtins.filter (u: u.isNormalUser))
              (map (
                user:
                let
                  u = toString (user.uid or user.name);
                  g = toString (user.gid or user.group);
                in
                [ "d /nix/var/nix/profiles/per-user/${user.name} 0750 ${u} ${g} - -" ]
              ))
              builtins.concatLists
            ];
          }
          (
            let
              timeout = cfg.initrd.emergency.rebootTimeout;
            in
            lib.mkIf (timeout > 0) {
              boot.initrd.systemd.services."emergency" = {
                overrideStrategy = "asDropin";
                postStart = ''
                  if ! /bin/systemd-ask-password --timeout=${toString timeout} \
                    --no-output --emoji=no \
                    "Are you there? Press enter to enter emergency shell."
                  then
                    /bin/systemctl reboot
                  fi
                '';
              };
            }
          )
          { home-manager.sharedModules = [ { kdn.development.git.enable = true; } ]; }
          {
            systemd.tmpfiles.rules = [
              "L /etc/nixos/flake.nix       - - - - flake.nix.rel"
              "L /etc/nixos/flake.nix.rel   - - - - /home/kdn/dev/github.com/nazarewk-iac/nix-configs/flake.nix"
              "L /etc/nixos/flake.nix.abs   - - - - ../../home/kdn/dev/github.com/nazarewk-iac/nix-configs/flake.nix"
            ];
          }
          { kdn.networking.tailscale.enable = false; }
          {
            kdn.networking.netbird.default.enable = false;
            kdn.networking.netbird.default.environment.NB_DISABLE_DNS = "true";
            kdn.networking.netbird.default.environment.NB_BLOCK_INBOUND = "true";
            kdn.networking.netbird.clients.priv.idx = 1;
            kdn.networking.netbird.clients.priv.enable = lib.mkDefault true;
            kdn.networking.netbird.clients.priv.environment.NB_DISABLE_DNS = "false";
            kdn.networking.netbird.clients.priv.environment.NB_BLOCK_INBOUND = "false";
            kdn.networking.netbird.clients.t1.idx = 5;
            kdn.networking.netbird.clients.t2.idx = 6;
            kdn.networking.netbird.clients.t3.idx = 7;
          }
          { kdn.services.nextcloud-client-nixos.enable = config.kdn.security.secrets.allowed; }
          (lib.mkIf config.kdn.security.secrets.allowed {
            systemd.services.sops-install-secrets.postStart = ''
              chmod -R go+r /run/configs
            '';
          })
          (
            let
              kernelParams = [
                "systemd.log_level=debug"
                "systemd.debug_shell=1"
                "systemd.default_debug_tty=tty9"
                "rd.systemd.debug_shell=1"
                "rd.systemd.default_debug_tty=tty10"
              ];
            in
            lib.mkIf (config.boot.initrd.systemd.enable) {
              specialisation.emergency = {
                inheritParentConfig = true;
                configuration = {
                  systemd.defaultUnit = lib.mkForce "emergency.target";
                  system.nixos.tags = [ "emergency" ];
                  boot.kernelParams = kernelParams;
                };
              };
              specialisation.rescue = {
                inheritParentConfig = true;
                configuration = {
                  systemd.defaultUnit = lib.mkForce "rescue.target";
                  system.nixos.tags = [ "rescue" ];
                  boot.kernelParams = kernelParams;
                };
              };
              specialisation.boot-debug = {
                inheritParentConfig = true;
                configuration = {
                  system.nixos.tags = [ "boot-debug" ];
                  boot.kernelParams = kernelParams;
                };
              };
              systemd.services."debug-shell" = {
                overrideStrategy = "asDropinIfExists";
              };
              boot.initrd.systemd.services."debug-shell" = {
                overrideStrategy = "asDropinIfExists";
              };
            }
          )
        ]
      ))
    ]
  );
}
