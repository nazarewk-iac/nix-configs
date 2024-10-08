{ config, pkgs, lib, osConfig, ... }@arguments:
let
  cfg = config.kdn.profile.user.kdn;
  systemUser = cfg.osConfig;
  hasGUI = config.kdn.headless.enableGUI;
  hasSway = config.kdn.desktop.sway.enable;
  hasWorkstation = osConfig.kdn.profile.machine.workstation.enable;
  hasKDE = osConfig.services.xserver.desktopManager.plasma5.enable;

  nc.rel = "Nextcloud/drag0nius@nc.nazarewk.pw";
  nc.abs = "${config.home.homeDirectory}/${nc.rel}";

  pow = n: i:
    if i == 1 then n
    else if i == 0 then 1
    else n * pow n (i - 1);
in
{
  options.kdn.profile.user.kdn = {
    enable = lib.mkEnableOption "me (kdn) account setup";

    osConfig = lib.mkOption { default = { }; };
  };
  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      kdn.programs.ssh-client.enable = true;
      home.file.".ssh/config.d/signicat.config".source = config.lib.file.mkOutOfStoreSymlink "/run/configs/networking/ssh_config/signicat";
      home.file.".ssh/config.d/kdn.config".source = config.lib.file.mkOutOfStoreSymlink "/run/configs/networking/ssh_config/kdn";

      # pam-u2f expects a single line of configuration per user in format `username:entry1:entry2:entry3:...`
      # `pamu2fcfg` generates lines of format `username:entry`
      # For ease of use you can append those pamu2fcfg to ./yubico/u2f_keys.parts directly,
      #  then below code will take care of stripping comments and folding it into a single line per user
      xdg.configFile."Yubico/u2f_keys".text =
        let
          stripComments = lib.filter (line: (builtins.match "\w*" line) != [ ] && (builtins.match "\w*#.*" line) != [ ]);
          groupByUsername = input: builtins.mapAttrs (name: map (lib.removePrefix "${name}:")) (lib.groupBy (e: lib.head (lib.splitString ":" e)) input);
          toOutputLines = lib.mapAttrsToList (name: values: (builtins.concatStringsSep ":" (lib.concatLists [ [ name ] values ])));

          foldParts = path: lib.trivial.pipe path [
            builtins.readFile
            (lib.splitString "\n")
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
      home.activation = {
        linkPasswordStore =
          lib.hm.dag.entryBetween [ "linkGeneration" ] [ "writeBoundary" ] ''
            $DRY_RUN_CMD ln -sfT "${nc.rel}/important/password-store" "$HOME/.password-store"
          '';
      };
      programs.password-store.enable = true;
      programs.password-store.settings = {
        PASSWORD_STORE_DIR = "${config.home.homeDirectory}/.password-store";
        PASSWORD_STORE_CLIP_TIME = "10";
      };
    }
    (lib.mkIf hasWorkstation {
      home.persistence."usr/data".directories = [
        "dev"
      ];

      kdn.services.syncthing.enable = true;
      kdn.programs.weechat.enable = true;
      programs.gh.enable = false;
      programs.gh.gitCredentialHelper.enable = false;
      programs.git.enable = true;
      # programs.git.signing.key = "CDDFE1610327F6F7A693125698C23F71A188991B";
      programs.git.signing.key = null;
      programs.git.signing.signByDefault = true;
      programs.git.userName = systemUser.description;
      programs.git.userEmail = "gpg@kdn.im";
      programs.git.ignores = [ (builtins.readFile ./.gitignore.tpl) ];
      programs.git.attributes = [ (builtins.readFile ./.gitattributes) ];
      # to authenticate hub: ln -s ~/.config/gh/hosts.yml ~/.config/hub
      programs.git.extraConfig = {
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
    })
    (lib.mkIf hasWorkstation {
      programs.git.extraConfig = {
        credential."https://gitlab.com/signicat/".username = "signicat-krznaz";
        url."https://gitlab.com/signicat/".insteadOf = "git@gitlab.com:signicat/";
      };
      home.persistence."usr/cache".directories = [
        ".cache/signicat"
      ];
      home.persistence."usr/config".directories = [
        ".config/signicat"
      ];
      home.persistence."usr/state".directories = [
        ".local/state/signicat"
      ];
      home.persistence."usr/data".directories = [
        ".local/share/signicat"
      ];
    })
    (lib.mkIf hasGUI {
      # KDE Connect
      services.kdeconnect.enable = true;
      services.kdeconnect.indicator = true;
      home.persistence."usr/config".directories = [
        ".config/kdeconnect"
      ];
    })
    (lib.mkIf hasGUI {
      # Firefox
      # TODO: manage settings?
      /* TODO: integrate with link opener?
          - addon https://github.com/nix-community/nur-combined/blob/959f71d785bcf7f241ebaa0c8c054eac4d6c19dd/repos/rycee/pkgs/firefox-addons/generated-firefox-addons.nix#L5876
          - launcher https://github.com/honsiorovskyi/open-url-in-container/blob/master/bin/launcher.sh
      */
      programs.firefox = {
        enable = true;
        profiles.kdn = {
          id = 0;
          isDefault = true;
        };
      };
    })
    (
      # TODO: extract it to separate module
      let
        ffCfg = config.programs.firefox;
        inherit (pkgs.stdenv.hostPlatform) isDarwin;
        profilesPath =
          if isDarwin then "${ffCfg.configPath}/Profiles" else ffCfg.configPath;

        containerProfilesList = lib.pipe config.programs.firefox.profiles [
          builtins.attrValues
          (builtins.filter (p: p.containers != { }))
        ];

        firefoxProfilePathsRel = lib.pipe containerProfilesList [
          (builtins.map (profile: "${profilesPath}/${profile.path}"))
        ];
      in
      lib.mkIf (firefoxProfilePathsRel != { }) {
        home.file = lib.pipe firefoxProfilePathsRel [
          (builtins.map (path: {
            name = "${path}/containers.json";
            value.target = "${path}/containers.json.d/50-hm-containers.json";
          }))
          builtins.listToAttrs
        ];

        systemd.user.paths.firefox-containers-d-sync = {
          Install.WantedBy = [ "default.target" ];
          Unit = {
            Description = "merges pieces into Firefox's containers.json file";
          };
          Path = {
            PathChanged = lib.pipe firefoxProfilePathsRel [
              (builtins.map (path: "${config.home.homeDirectory}/${path}/containers.json.d"))
            ];
            TriggerLimitBurst = "1";
            TriggerLimitIntervalSec = "1s";
          };
        };
        systemd.user.services.firefox-containers-d-sync = {
          Install.WantedBy = [ "default.target" ];
          Unit = {
            Description = "merges pieces into Firefox's containers.json file";
          };
          Service = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = lib.strings.escapeShellArgs [
              (lib.getExe pkgs.kdn.ff-ctl)
              "containers-config-render"
            ];
          };
        };
        home.packages = with pkgs; [
          kdn.ff-ctl
        ];
      }
    )
    (lib.mkIf (hasGUI && config.kdn.hardware.disks.enable) {
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
          color = "turquoise";
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
          color = "toolbar";
        };
      };
    })
    (lib.mkIf hasGUI {
      home.persistence."usr/reproducible".directories = [
        "Nextcloud"
      ];

      services.nextcloud-client.enable = true;
      /* TODO: try an automated login on activation using `sops-nix` credentials?
          - make sure at least password-store & Keepass are downloaded (and not much more)
      */
      services.nextcloud-client.startInBackground = true;
      systemd.user.services.nextcloud-client.Service = {
        Restart = "on-failure";
        RestartSec = 3;
      };
    })
    (lib.mkIf hasGUI {
      # see https://github.com/nix-community/home-manager/issues/2104#issuecomment-861676751
      home.file."${nc.rel}/images/screenshots/.keep".source = builtins.toFile "keep" "";
      services.flameshot.settings.General.savePath = "${nc.abs}/images/screenshots";
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
          categories = [ "Network" "WebBrowser" ];
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
    (lib.mkIf hasGUI {
      /* TODO: configure programatically (View > Settings):
            - SSH Agent
              - Enable ... integration
            - Secret Service Integration
              - Enable ... integration
              - untick all except `Prompt to unlock database before searching`
            - General
              - Startup
                - disable remembering previous databases
                - disable showing expired entries
              - Entry Management
                - `hide window when copying to clipboard` set to `Drop to background`
              - User Interface
                - Show a system tray icon
                  - colorful
                  - hide to tray when minimized
            - Security
              - Convenience
                - `Lock databases when session is locked or lid is closed`: false
              - Privacy
                - use DDG for favicons
            - Browser Integration
              - Enable ... integration
              - enable for Firefox only
              - search in all opened databases
        */
      # TODO: entries list an entry preview were invisible, had to drag-resize from the edge
      home.sessionVariables = {
        KEEPASS_PATH = "${nc.abs}/important/keepass";
      };
      systemd.user.services.keepassxc = {
        Unit.Description = "KeePassXC password manager";
        Service = {
          Type = "notify";
          NotifyAccess = "all";
          Environment = [ "KEEPASS_PATH=${nc.abs}/important/keepass" ];
          Slice = "background.slice";
          ExecStart = "${lib.getExe pkgs.kdn.kdn-keepass} drag0nius.kdbx";
        };
        Unit = {
          ConditionPathExists = "${nc.abs}/important/keepass";
        };
        Install.WantedBy = [ "graphical-session.target" ];
      };
      home.persistence."usr/config".directories = [
        ".config/keepassxc"
      ];
    })
    (lib.mkIf hasSway (import ./mimeapps.nix arguments).config)
    (lib.mkIf hasSway {
      systemd.user.services.keepassxc.Unit = {
        BindsTo = config.kdn.desktop.sway.systemd.secrets-service.service;
        Requires = [ config.kdn.desktop.sway.systemd.envs.target ];

        After = [ config.kdn.desktop.sway.systemd.envs.target ];
        PartOf = [ config.kdn.desktop.sway.systemd.session.target ];
      };
      systemd.user.services.keepassxc.Install.WantedBy = [ config.kdn.desktop.sway.systemd.secrets-service.service ];

      systemd.user.services.nextcloud-client.Unit = {
        Requires = lib.mkForce [
          config.kdn.desktop.sway.systemd.envs.target
          config.kdn.desktop.sway.systemd.secrets-service.service
        ];
        After = [
          config.kdn.desktop.sway.systemd.secrets-service.service
          config.kdn.desktop.sway.systemd.envs.target
          "tray.target"
        ];
        PartOf = [ config.kdn.desktop.sway.systemd.session.target ];
      };
      systemd.user.services.nextcloud-client.Install = {
        WantedBy = [ config.kdn.desktop.sway.systemd.session.target ];
      };
      systemd.user.services.kdeconnect.Unit = {
        Requires = [ config.kdn.desktop.sway.systemd.envs.target ];
        After = [ config.kdn.desktop.sway.systemd.envs.target ];
        PartOf = [ config.kdn.desktop.sway.systemd.session.target ];
      };
      systemd.user.services.kdeconnect-indicator.Unit = {
        Requires = [ config.kdn.desktop.sway.systemd.envs.target "kdeconnect.service" ];
        After = [ "tray.target" config.kdn.desktop.sway.systemd.envs.target "kdeconnect.service" ];
        PartOf = [ config.kdn.desktop.sway.systemd.session.target ];
      };
    })
    (lib.mkIf (hasWorkstation && hasGUI) {
      home.packages = with pkgs; [
        kdn.klog-time-tracker
        kdn.klg
      ];
      xdg.configFile."klg/config.toml".source = config.lib.file.mkOutOfStoreSymlink "${nc.abs}/time-logs/klg/config.toml";
    })
    (lib.mkIf (hasWorkstation && hasGUI) {
      home.packages = with pkgs; [
        keepassxc
        kdn.kdn-keepass
        (pkgs.writeShellApplication {
          name = "kdn-drag0nius.kdbx";
          text = "${lib.getExe pkgs.kdn.kdn-keepass} drag0nius.kdbx";
        })
        bitwarden
        bitwarden-cli

        flameshot
        vlc
        subtitleedit
        subtitleeditor
        (ffsubsync.override { python3 = pkgs.python39; })
        haruna
        shotwell

        qrencode
        #cobang # QR code scanner # 2024-01-23: dependency failed to build
        zbar # QR/BAR CODE READER: `zbarimg /path/to.img
        imagemagick

        logseq
        kdn.ss-util
        drawio
        plantuml

        zoom-us
        nextcloud-client

        deluge

        httpie-desktop
      ];
    })
    (lib.mkIf (hasWorkstation && hasGUI) {
      home.packages = with pkgs; [
        ungoogled-chromium
      ];
      home.persistence."usr/config".directories = [
        ".config/chromium"
      ];
    })
    (lib.mkIf (hasWorkstation && hasGUI) {
      home.packages = with pkgs; [
        spotifywm
      ];
      home.persistence."usr/cache".directories = [
        ".cache/spotify"
      ];
      home.persistence."usr/config".directories = [
        ".config/spotify"
      ];
    })
    (lib.mkIf (hasWorkstation && hasGUI) {
      home.packages = with pkgs; [
        signal-desktop
      ];
      home.persistence."usr/config".directories = [
        ".config/Signal"
      ];
    })
    (lib.mkIf (hasWorkstation && hasGUI) {
      home.packages = with pkgs; [
        element-desktop
      ];
      home.persistence."usr/config".directories = [
        ".config/Element"
      ];
    })
    (lib.mkIf (hasWorkstation && hasGUI) {
      home.packages = with pkgs; [
        slack
      ];
      home.persistence."usr/config".directories = [
        ".config/Slack"
      ];
    })
    (lib.mkIf (hasWorkstation && hasGUI) {
      home.packages = with pkgs; [
        rambox # browser/multi workspace
      ];
      home.persistence."usr/config".directories = [
        ".config/rambox"
      ];
    })
    (lib.mkIf (hasWorkstation && hasGUI) {
      home.packages = with pkgs; [
        kdn.ente-photos-desktop
      ];
      home.persistence."usr/cache".directories = [
        ".cache/ente"
      ];
      home.persistence."usr/config".directories = [
        ".config/ente"
      ];
    })
    ({
      programs.helix.enable = true;
      programs.helix.settings.theme = "darcula-solid";
      stylix.targets.helix.enable = false;
    })
  ]);
}
