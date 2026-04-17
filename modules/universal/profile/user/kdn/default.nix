{
  lib,
  config,
  kdnConfig,
  pkgs,
  osConfig ? { },
  ...
}:
let
  cfg = config.kdn.profile.user.kdn;

  nc.rel = "Nextcloud/drag0nius@nc.nazarewk.pw";
  hasWorkstation = (osConfig.kdn or { }).profile.machine.workstation.enable or false;
in
{
  options.kdn.profile.user.kdn = {
    enable = lib.mkEnableOption "enable my user profiles";
    ssh = lib.mkOption {
      readOnly = true;
      default =
        let
          authorizedKeysPath = ./.ssh/authorized_keys;
          authorizedKeysList = lib.trivial.pipe authorizedKeysPath [
            builtins.readFile
            (lib.strings.splitString "\n")
          ];
        in
        {
          inherit authorizedKeysList authorizedKeysPath;

          authorizedKeysText = builtins.concatStringsSep "\n" authorizedKeysList;
        };
    };
    gpg.publicKeys = lib.mkOption {
      type = with lib.types; path;
      readOnly = true;
      default = pkgs.writeText "kdn-gpg-pubkeys.txt" (builtins.readFile ./gpg-pubkeys.txt);
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
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
        ];
      }
      # home-manager
      (kdnConfig.util.ifHM (
        lib.mkMerge [
          {
            kdn.programs.ssh-client.enable = true;
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
            programs.gpg.publicKeys = [
              {
                source = cfg.gpg.publicKeys;
                trust = "ultimate";
              }
            ];
            home.activation = {
              linkPasswordStore = lib.hm.dag.entryBetween [ "linkGeneration" ] [ "writeBoundary" ] ''
                $DRY_RUN_CMD ln -sfT "${nc.rel}/important/password-store" "$HOME/.password-store"
              '';
            };
          }
          # kdn.programs.password-store.enable = true; # currently inside gnupg
          {
            programs.gh.enable = false;
            programs.gh.gitCredentialHelper.enable = false;
            # programs.git.signing.key = "CDDFE1610327F6F7A693125698C23F71A188991B";
            programs.git.signing.key = null;
            programs.git.signing.format = "openpgp"; # 2023-03-23: default changed to null
            programs.git.signing.signByDefault = true;
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
              user.name = "Krzysztof Nazarewski";
              user.email = "gpg@kdn.im";
              signing.behavior = "own";
              signing.backend = "gpg";
            };
          }
          (lib.mkIf (hasWorkstation) {
            kdn.disks.persist."usr/data".directories = [ "dev" ];
            kdn.services.syncthing.enable = true;
            kdn.programs.weechat.enable = true;
          })
          (lib.mkIf config.kdn.programs.firefox.enable (
            lib.mkMerge [
              {
                # Firefox
                # don't search/expand single-word searchbars
                programs.firefox.policies.GoToIntranetSiteForSingleWordEntryInAddressBar = true;
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
            # see https://github.com/nix-community/home-manager/issues/2104#issuecomment-861676751
            home.file."${nc.rel}/images/screenshots/.keep".source = builtins.toFile "keep" "";
            services.flameshot.settings.General.savePath =
              "${config.home.homeDirectory}/${nc.rel}/images/screenshots";
            xdg.configFile."gsimplecal/config".source = ./gsimplecal/config;
            xdg.mime.enable = true;
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
            kdn.programs.keepassxc.enable = true;
            kdn.programs.keepassxc.service.enable = true;
            kdn.programs.keepassxc.service.searchDirs = [
              "${config.home.homeDirectory}/${nc.rel}/important/keepass"
            ];
            kdn.programs.keepassxc.service.fileName = "drag0nius.kdbx";
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
          (lib.mkIf (hasWorkstation) {
            kdn.env.packages = with pkgs; [
              pkgs.kdn.klog-time-tracker
              pkgs.kdn.klg
            ];
            xdg.configFile."klg/config.toml".source =
              config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/${nc.rel}/time-logs/klg/config.toml";
          })
          (lib.mkIf ((hasWorkstation) && config.kdn.desktop.enable) {
            kdn.env.packages = with pkgs; [
              (pkgs.writeShellApplication {
                name = "kdn-drag0nius.kdbx";
                text = "${lib.getExe pkgs.kdn.kdn-keepass} drag0nius.kdbx";
              })
              flameshot
              vlc
              subtitleedit
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
          (lib.mkIf ((hasWorkstation) && config.kdn.desktop.enable) {
            kdn.programs.beeper.enable = true;
            kdn.programs.browsers.enable = true;
            kdn.programs.chrome.enable = true;
            kdn.programs.chromium.enable = true;
            kdn.programs.matrix.enable = true;
            kdn.programs.ente-photos.enable = true;
            kdn.programs.logseq.enable = true;
            kdn.programs.nextcloud-client.enable = true;
            kdn.programs.rambox.enable = true;
            kdn.programs.signal.enable = true;
            kdn.programs.slack.enable = true;
            kdn.programs.spotify.enable = true;
            kdn.programs.tidal.enable = true;
            kdn.programs.torrent.enable = true;
            kdn.toolset.print-3d.enable = true;
          })
          (lib.mkIf pkgs.stdenv.isDarwin {
            kdn.env.packages = with pkgs; [ realvnc-vnc-viewer ];
          })
        ]
      ))
      # nixos
      # shared darwin-nixos
      # shared darwin-nixos
      (kdnConfig.util.ifTypes [ "nixos" "darwin" ] {
        users.users.kdn = {
          description = "Krzysztof Nazarewski";
          openssh.authorizedKeys.keys = cfg.ssh.authorizedKeysList;
        };
      })
      # darwin
      (kdnConfig.util.ifTypes [ "darwin" ] (
        lib.mkMerge [
          { home-manager.users.kdn.kdn.profile.user.kdn.enable = true; }
          {
            system.primaryUser = lib.mkDefault "kdn";
            nix-homebrew.user = "kdn";
            users.users.kdn.home = "/Users/kdn";
          }
        ]
      ))
      # nixos
      (kdnConfig.util.ifTypes [ "nixos" ] (
        lib.mkMerge [
          {
            nix.settings.trusted-users = [ "kdn" ];
            kdn.programs.atuin.users = [ "kdn" ];
            kdn.programs.atuin.autologinUsers = [ "kdn" ];
            kdn.hw.yubikey.appId = "pam://kdn";
            users.users.kdn.initialHashedPassword = "$y$j9T$yl3J5zGJ5Yq8c6fXMGxNk.$XE3X8aWpD3FeakMBD/fUmCExXMuy7B6tm7ZECmuxpF4";
            users.users.kdn = {
              linger = true;
              uid = 31893;
              isNormalUser = true;
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
          }
          {
            home-manager.users.kdn.kdn.profile.user.kdn.enable = true;
            home-manager.users.root.programs.gpg.publicKeys = [
              {
                source = cfg.gpg.publicKeys;
                trust = "ultimate";
              }
            ];
          }
          {
            kdn.networking.netbird.admins = [ "kdn" ];
          }
        ]
      ))
    ]
  );
}
