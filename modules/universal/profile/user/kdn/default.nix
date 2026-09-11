{
  lib,
  config,
  kdnConfig,
  pkgs,
  ...
}:
let
  cfg = config.kdn.profile.user.kdn;

  nc.rel = "Nextcloud/drag0nius@nc.nazarewk.pw";
  hasWorkstation = config.kdn.profile.machine.workstation.enable;
in
{
  options.kdn.profile.user.kdn = {
    enable = lib.mkEnableOption "enable my user profiles";

    /*
      The four switches below split one bundle into one concern per switch.

      One user profile used to turn on the LLM harnesses, a version-control identity, a file-sync
      layout and a browser profile set together. An adopter who reuses this profile wants some of
      them and not the rest. A version-control identity and a browser profile set carry a real name,
      so they are the first two an adopter drops.

      Each default is `true`, the value this repository uses today. A `true` default costs nothing
      when `enable` is `false`, because the whole `config` sits behind `enable`. An adopter writes a
      plain `false`, which wins over the `mkDefault` forward into Home Manager.
    */
    llm.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      example = false;
      description = "Turn on the LLM harnesses of this tree on a development machine.";
    };
    vcsIdentity.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      example = false;
      description = "Write the git and jj identity, the signing choice and the credential helper.";
    };
    nextcloud.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      example = false;
      description = "Point the password store, the screenshots and the time logs at the sync share.";
    };
    firefoxProfiles.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      example = false;
      description = "Declare the named Firefox profiles and containers of this tree.";
    };

    username = lib.mkOption {
      type = with lib.types; str;
      default = "kdn";
    };
    homeDir = lib.mkOption {
      readOnly = true;
      type = with lib.types; str;
      default =
        if
          kdnConfig.util.isOfType [
            "nixos"
            "darwin"
          ]
        then
          config.users.users.kdn.home
        else if kdnConfig.util.isOfType [ "home-manager" ] then
          config.home.homeDirectory
        else
          "/home/${cfg.username}";
    };
    ssh.authorizedKeysFile = lib.mkOption {
      type = with lib.types; nullOr path;
      default = if builtins.pathExists ./.ssh/authorized_keys then ./.ssh/authorized_keys else null;
      description = ''
        File that seeds `ssh.authorizedKeysList`, one key per line.
        `null` means the tree carries no key file, so the list starts empty.
      '';
    };
    ssh.authorizedKeysList = lib.mkOption {
      type = with lib.types; listOf str;
      default =
        if cfg.ssh.authorizedKeysFile == null then
          [ ]
        else
          lib.strings.splitString "\n" (builtins.readFile cfg.ssh.authorizedKeysFile);
      description = "Public keys of the user account. An adopter sets their own list here.";
    };
    ssh.authorizedKeysText = lib.mkOption {
      type = with lib.types; str;
      default = builtins.concatStringsSep "\n" cfg.ssh.authorizedKeysList;
      description = "`authorizedKeysList` as one text block.";
    };
    ssh.authorizedKeysPath = lib.mkOption {
      type = with lib.types; path;
      default = pkgs.writeText "kdn-authorized-keys" cfg.ssh.authorizedKeysText;
      description = ''
        `authorizedKeysList` as a file, for an `openssh.authorizedKeys.keyFiles` reader.
        The content equals the seed file, so the reader sees the same bytes as before.
      '';
    };
    gpg.publicKeys = lib.mkOption {
      type = with lib.types; nullOr path;
      default =
        if builtins.pathExists ./gpg-pubkeys.txt then
          pkgs.writeText "kdn-gpg-pubkeys.txt" (builtins.readFile ./gpg-pubkeys.txt)
        else
          null;
      description = "GPG keyring to trust. `null` means the tree carries no keyring.";
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      (lib.mkIf cfg.llm.enable {
        # Enable the LLM harnesses only on a development machine, not on servers.
        kdn.development.llm.claude-code.enable = lib.mkDefault config.kdn.profile.machine.dev.enable;
        kdn.development.llm.opencode.enable = lib.mkDefault config.kdn.profile.machine.dev.enable;
        kdn.development.llm.pi.enable = lib.mkDefault config.kdn.profile.machine.dev.enable;
        /*
          TODO: 2026-09-10 — turn omp back on once it builds on the arm64 Darwin build path.

          omp cannot build in the x86_64 Rosetta guest, for two independent reasons and neither of
          them is a defect here:
            1. The upstream [profile.release] uses lto = "fat" and codegen-units = 1, so rustc
               dies with SIGKILL in the 6 GiB guest while it links jj-lib.
            2. installCheckPhase runs `omp --smoke-test`, which forks `omp lsp mux` and then
               blocks. Measured 11m52s elapsed against 4s of CPU time at load 0.11. More guest
               memory does not change this.
          Both hosts that want omp run x86_64 natively with far more memory, so neither blocker
          exists there. Revert this line, do not build on it.
        */
        kdn.development.llm.omp.enable = lib.mkDefault false;
      })
      {
        kdn.env.packages = with pkgs; [
          kdn.kdnctl
          # (yt-dlp.overrideAttrs (final: {
          #   version = "2025.09.26";
          #   src = pkgs.fetchFromGitHub {
          #     owner = "yt-dlp";
          #     repo = "yt-dlp";
          #     tag = final.version;
          #     hash = "sha256-/uzs87Vw+aDNfIJVLOx3C8RyZvWLqjggmnjrOvUX1Eg=";
          #   };
          # }))
          kdn.kagi-cli
        ];
        /*
          Keep the literal `kdn`. These three lists hold **system user attribute names**, and this
          module declares its account as `users.users.kdn` everywhere. `cfg.username` holds the
          login name, which is not the same string on every host. A measurement on 2026-09-11 read
          `["root", "<login>"]` on one host where the two differ, and a new
          `home-manager.users.<login>` appeared with it. `yubikey.appId` and `netbird.admins` want
          the login name, so they keep `cfg.username`.
        */
        kdn.programs.atuin.users = [ "kdn" ];
        kdn.programs.fish.defaultShellUsers = [ "kdn" ];
        kdn.hw.yubikey.appId = "pam://${cfg.username}";
        kdn.programs.atuin.autologinUsers = [ "kdn" ];
        kdn.networking.netbird.admins = [ cfg.username ];
      }
      (lib.mkIf hasWorkstation {
        kdn.env.packages = with pkgs; [
          pkgs.kdn.klog-time-tracker
          pkgs.kdn.klg
        ];
      })
      (kdnConfig.util.ifHMParent {
        home-manager.users.kdn.kdn.profile.user.kdn = {
          enable = lib.mkDefault true;
          username = cfg.username;
          # Forward the per-concern switches, so one host-side `false` reaches Home Manager too.
          vcsIdentity.enable = lib.mkDefault cfg.vcsIdentity.enable;
          nextcloud.enable = lib.mkDefault cfg.nextcloud.enable;
          firefoxProfiles.enable = lib.mkDefault cfg.firefoxProfiles.enable;
        };
        home-manager.users.root.programs.gpg.publicKeys = lib.optionals (cfg.gpg.publicKeys != null) [
          {
            source = cfg.gpg.publicKeys;
            trust = "ultimate";
          }
        ];
      })
      (kdnConfig.util.ifHM (
        lib.mkMerge [
          {
            kdn.programs.ssh-client.enable = lib.mkDefault true;
            home.file.".ssh/config.d/kdn.config".source =
              config.lib.file.mkOutOfStoreSymlink "/run/configs/networking/ssh_config/kdn";

            # pam-u2f expects a single line of configuration per user in format `username:entry1:entry2:entry3:...`
            # `pamu2fcfg` generates lines of format `username:entry`
            # For ease of use you can append those pamu2fcfg to ./yubico/u2f_keys.parts directly,
            #  then below code will take care of stripping comments and folding it into a single line per user
            xdg.configFile."Yubico/u2f_keys".text =
              let
                stripComments = lib.filter (line: (builtins.match "[[:space:]]*(#.*)?" line) == null);
                groupByUsername =
                  input:
                  builtins.mapAttrs (name: map (lib.removePrefix "${name}:")) (
                    lib.groupBy (e: lib.head (lib.strings.splitString ":" e)) input
                  );
                toOutputLines = lib.attrsets.mapAttrsToList (
                  name: values:
                  (builtins.concatStringsSep ":" (
                    lib.concatLists [
                      [ name ]
                      values
                    ]
                  ))
                );

                foldParts =
                  path:
                  lib.trivial.pipe path [
                    builtins.readFile
                    (lib.strings.splitString "\n")
                    stripComments
                    groupByUsername
                    (lib.attrsets.filterAttrs (n: v: n == config.home.username))
                    toOutputLines
                    (builtins.concatStringsSep "\n")
                  ];
              in
              foldParts ./yubico/u2f_keys.parts;
          }
          {
            # GPG
            programs.gpg.publicKeys = lib.optionals (cfg.gpg.publicKeys != null) [
              {
                source = cfg.gpg.publicKeys;
                trust = "ultimate";
              }
            ];
          }
          (lib.mkIf cfg.nextcloud.enable {
            home.activation = {
              linkPasswordStore = lib.hm.dag.entryBetween [ "linkGeneration" ] [ "writeBoundary" ] ''
                $DRY_RUN_CMD ln -sfT "${nc.rel}/important/password-store" "$HOME/.password-store"
              '';
            };
          })
          # kdn.programs.password-store.enable = true; # currently inside gnupg
          (lib.mkIf cfg.vcsIdentity.enable {
            programs.gh.enable = false;
            programs.gh.gitCredentialHelper.enable = false;
            # programs.git.signing.key = "CDDFE1610327F6F7A693125698C23F71A188991B";
            programs.git.signing.key = null;
            programs.git.signing.format = "openpgp"; # 2023-03-23: default changed to null
            programs.git.signing.signByDefault = lib.mkDefault true;
            programs.git.ignores = [ (builtins.readFile ./.gitignore.tpl) ];
            programs.git.attributes = [ (builtins.readFile ./.gitattributes) ];
            # to authenticate hub: ln -s ~/.config/gh/hosts.yml ~/.config/hub
            programs.git.settings = {
              user.name = "Krzysztof Nazarewski";
              user.email = "gpg@kdn.im";
              credential.helper =
                let
                  wrapped = pkgs.writeShellApplication {
                    name = "git-credential-keyring-wrapped";
                    runtimeInputs = [ pkgs.kdn.git-credential-keyring ];
                    text = ''
                      export PYTHON_KEYRING_BACKEND="keyring_pass.PasswordStoreBackend"
                      export KEYRING_PROPERTY_PASS_BINARY="${pkgs.pass}/bin/pass"
                      export GIT_CREDENTIAL_KEYRING_IGNORE_DELETIONS=1
                      git-credential-keyring "$@"
                    '';
                  };
                in
                "${wrapped}/bin/git-credential-keyring-wrapped";

              credential."https://github.com".username = "nazarewk";
              url."https://github.com/".insteadOf = "git@github.com:";
              credential."https://gist.github.com".username = "nazarewk";
              url."https://gist.github.com/".insteadOf = "git@gist.github.com:";
            };
            programs.jujutsu.settings = {
              user.name = config.programs.git.settings.user.name;
              user.email = config.programs.git.settings.user.email;
              signing.behavior = "own";
              signing.backend = "gpg";
            };
          })
          (lib.mkIf hasWorkstation {
            kdn.disks.persist."usr/data".directories = [ "dev" ];
            kdn.services.syncthing.enable = lib.mkDefault true;
            kdn.programs.weechat.enable = lib.mkDefault true;
          })
          (lib.mkIf (config.kdn.programs.firefox.enable && cfg.firefoxProfiles.enable) (
            lib.mkMerge [
              {
                # Firefox
                # don't search/expand single-word searchbars
                programs.firefox.policies.GoToIntranetSiteForSingleWordEntryInAddressBar = lib.mkDefault true;
                kdn.programs.firefox.profileNames = [ "kdn" ];
                programs.firefox.profiles.kdn = {
                  id = 0;
                  settings."widget.use-xdg-desktop-portal.mime-picker" = "1";
                  settings."intl.accept_languages" = "en-gb,en-us,en,pl";
                  settings."intl.locale.requested" = "en";
                };
                programs.firefox.profiles.kdn.containers = {
                  personal = {
                    id = 1;
                    icon = "fingerprint";
                    color = "blue";
                  };
                  personal-2 = {
                    id = 2;
                    icon = "fingerprint";
                    color = "green";
                  };
                  work = {
                    id = 3;
                    icon = "briefcase";
                    color = "turquoise";
                  };
                  work-2 = {
                    id = 4;
                    icon = "briefcase";
                    color = "purple";
                  };
                  en = {
                    id = 5;
                    icon = "pet";
                    color = "red";
                  };
                  bn = {
                    id = 6;
                    icon = "pet";
                    color = "pink";
                  };
                  sn = {
                    id = 7;
                    icon = "pet";
                    color = "purple";
                  };
                  Facebook = {
                    id = 8;
                    icon = "fence";
                    color = "yellow";
                  };
                };
              }
              {
                kdn.programs.firefox.profileNames = [ "jp" ];
                programs.firefox.profiles.jp.id = 1;
              }
              {
                kdn.programs.firefox.profileNames = [ "bn" ];
                programs.firefox.profiles.bn.id = 2;
              }
              {
                kdn.programs.firefox.profileNames = [ "sn" ];
                programs.firefox.profiles.sn.id = 3;
              }
              {
                kdn.programs.firefox.profileNames = [ "en" ];
                programs.firefox.profiles.en.id = 4;
              }
              {
                kdn.programs.firefox.profileNames = [ "dn" ];
                programs.firefox.profiles.dn.id = 5;
              }
            ]
          ))
          (lib.mkIf config.kdn.desktop.enable {
            xdg.configFile."gsimplecal/config".source = ./gsimplecal/config;
          })
          (lib.mkIf (config.kdn.desktop.enable && cfg.nextcloud.enable) {
            # see https://github.com/nix-community/home-manager/issues/2104#issuecomment-861676751
            home.file."${nc.rel}/images/screenshots/.keep".source = builtins.toFile "keep" "";
            services.flameshot.settings.General.savePath =
              "${config.home.homeDirectory}/${nc.rel}/images/screenshots";
          })
          (lib.mkIf (config.kdn.desktop.enable && kdnConfig.util.hasParentOfAnyType [ "nixos" ]) {
            xdg.mime.enable = lib.mkDefault true;
            xdg.desktopEntries.uri-to-clipboard =
              let
                bin = pkgs.writeShellScript "uri-to-clipboard" ''
                  set -eEuo pipefail
                  url="$1"
                  ${pkgs.libnotify}/bin/notify-send --expire-time=3000 "copied to clipboard" "$url"
                  ${pkgs.wl-clipboard}/bin/wl-copy "$url"
                '';
              in
              {
                name = "Copy URI to clipboard";
                noDisplay = false;
                genericName = "uri-to-clipboard";
                exec = "${bin} %U";
                categories = [
                  "Network"
                  "WebBrowser"
                ];
                mimeType = [
                  "application/x-extension-htm"
                  "application/x-extension-html"
                  "application/x-extension-shtml"
                  "application/x-extension-xht"
                  "application/x-extension-xhtml"
                  "application/xhtml+xml"
                  "application/xhtml_xml"
                  "x-scheme-handler/chrome"
                  "x-scheme-handler/http"
                  "x-scheme-handler/https"
                ];
              };
          })
          (lib.mkIf config.kdn.desktop.enable {
            kdn.programs.keepassxc.enable = lib.mkDefault true;
            kdn.programs.keepassxc.service.enable = lib.mkDefault true;
            kdn.programs.keepassxc.service.fileName = "drag0nius.kdbx";
          })
          # Only the search directory comes from the sync share, so it splits off from keepassxc.
          (lib.mkIf (config.kdn.desktop.enable && cfg.nextcloud.enable) {
            kdn.programs.keepassxc.service.searchDirs = [
              "${config.home.homeDirectory}/${nc.rel}/important/keepass"
            ];
          })
          (lib.mkIf (config.kdn.desktop.sway.enable)
            (import ./mimeapps.nix { inherit config pkgs lib; }).config
          )
          (lib.mkIf config.kdn.desktop.sway.enable {
            systemd.user.services.keepassxc.Unit = {
              BindsTo = config.kdn.desktop.sway.systemd.secrets-service.service;
              Requires = [ config.kdn.desktop.sway.systemd.envs.target ];
              After = [ config.kdn.desktop.sway.systemd.envs.target ];
              PartOf = [ config.wayland.systemd.target ];
            };
            systemd.user.services.keepassxc.Install.WantedBy = [
              config.kdn.desktop.sway.systemd.secrets-service.service
            ];
            systemd.user.services.nextcloud-client.Unit = {
              Requires = lib.mkForce [
                config.kdn.desktop.sway.systemd.envs.target
                config.kdn.desktop.sway.systemd.secrets-service.service
              ];
              After = [
                config.wayland.systemd.target
                config.kdn.desktop.sway.systemd.secrets-service.service
                config.kdn.desktop.sway.systemd.envs.target
                "tray.target"
              ];
              PartOf = [ config.wayland.systemd.target ];
            };
            systemd.user.services.nextcloud-client.Install.WantedBy = [ config.wayland.systemd.target ];
            systemd.user.services.kdeconnect.Unit = {
              Requires = [ config.kdn.desktop.sway.systemd.envs.target ];
              After = [ config.kdn.desktop.sway.systemd.envs.target ];
              PartOf = [ config.wayland.systemd.target ];
            };
            systemd.user.services.kdeconnect-indicator.Unit = {
              Requires = [
                config.kdn.desktop.sway.systemd.envs.target
                "kdeconnect.service"
              ];
              After = [
                "tray.target"
                config.kdn.desktop.sway.systemd.envs.target
                "kdeconnect.service"
              ];
              PartOf = [ config.wayland.systemd.target ];
            };
          })
          (lib.mkIf (hasWorkstation && cfg.nextcloud.enable) {
            # TODO: migrate to universal, split out a private instead of workstation profile?
            xdg.configFile."klg/config.toml".source =
              config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/${nc.rel}/time-logs/klg/config.toml";
          })
          (lib.mkIf (hasWorkstation && config.kdn.desktop.enable) {
            # TODO: migrate to universal, split out a private instead of workstation profile?
            kdn.env.packages = with pkgs; [
              (pkgs.writeShellApplication {
                name = "kdn-drag0nius.kdbx";
                text = "${lib.getExe pkgs.kdn.kdn-keepass} drag0nius.kdbx";
              })
              vlc
              #subtitleedit # 2026-09-09: removed from nixpkgs, it relies on gtk2
              subtitleeditor
              ffsubsync
              haruna
              shotwell
              qrencode
              #cobang # QR code scanner # 2024-01-23: dependency failed to build
              zbar # QR/BAR CODE READER: `zbarimg /path/to.img
              imagemagick
              pkgs.kdn.ss-util
              zoom-us
              nextcloud-client
              httpie-desktop
            ];
          })
          (lib.mkIf (hasWorkstation && config.kdn.desktop.enable) {
            # TODO: migrate to universal, split out a private instead of workstation profile?
            kdn.programs.beeper.enable = lib.mkDefault true;
            kdn.programs.matrix.enable = lib.mkDefault true;
            kdn.programs.ente-photos.enable = lib.mkDefault true;
            # kdn.programs.logseq.enable = true; # TODO: 2026-08-29: broken build
            kdn.programs.nextcloud-client.enable = lib.mkDefault true;
            kdn.programs.rambox.enable = lib.mkDefault true;
            kdn.programs.signal.enable = lib.mkDefault true;
            kdn.programs.slack.enable = lib.mkDefault true;
            kdn.programs.spotify.enable = lib.mkDefault true;
            kdn.programs.tidal.enable = lib.mkDefault true;
            kdn.programs.torrent.enable = lib.mkDefault true;
            kdn.toolset.print-3d.enable = lib.mkDefault true;
          })
          (lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
            kdn.env.packages = with pkgs; [
              # realvnc-vnc-viewer # TODO: 2026-04-24: broken SSL cert
            ];
          })
        ]
      ))
      (kdnConfig.util.ifTypes [ "nixos" "darwin" ] {
        users.users.kdn.description = "Krzysztof Nazarewski";
        users.users.kdn.openssh.authorizedKeys.keys = cfg.ssh.authorizedKeysList;
        users.users.kdn.name = cfg.username;
        nix.settings.trusted-users = [ cfg.username ];
      })
      (kdnConfig.util.ifTypes [ "darwin" ] {
        system.primaryUser = lib.mkDefault cfg.username;
        nix-homebrew.user = cfg.username;
        users.users.kdn.home = lib.mkDefault "/Users/${cfg.username}";
      })
      (kdnConfig.util.ifTypes [ "nixos" ] {
        users.users.kdn = {
          initialHashedPassword = "$y$j9T$yl3J5zGJ5Yq8c6fXMGxNk.$XE3X8aWpD3FeakMBD/fUmCExXMuy7B6tm7ZECmuxpF4";
          linger = lib.mkDefault true;
          uid = 31893;
          isNormalUser = true;
          subUidRanges = [
            {
              startUid = config.users.users.kdn.uid * 65536;
              count = 65536;
            }
          ];
          subGidRanges = [
            {
              startGid = config.users.users.kdn.uid * 65536;
              count = 65536;
            }
          ];
          extraGroups = lib.filter (group: lib.hasAttr group config.users.groups) [
            "adbusers"
            "audio"
            "deluge"
            "dialout"
            "docker"
            "kvm"
            "libvirtd"
            "lp"
            "lpadmin"
            "mlocate"
            "networkmanager"
            "pipewire"
            "plugdev"
            "podman"
            "power"
            "samba"
            "scanner"
            "tty"
            "video"
            "weechat"
            "wheel"
            "wireshark"
            "ydotool"
          ];
        };
        networking.firewall = {
          allowedTCPPorts = [ 22000 ];
          allowedUDPPorts = [
            21027
            22000
          ];
        };
      })
    ]
  );
}
