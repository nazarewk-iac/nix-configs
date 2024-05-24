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
in
{
  options.kdn.profile.user.kdn = {
    enable = lib.mkEnableOption "me (kdn) account setup";

    osConfig = lib.mkOption { default = { }; };
  };
  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      services.ssh-agent.enable = true;
      programs.ssh.enable = true;
      programs.ssh.extraConfig = ''
        Host *
          Include ~/.ssh/config.local
      '';

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
      kdn.services.syncthing.enable = true;
      kdn.programs.weechat.enable = true;
      programs.gh.enable = false;
      programs.gh.gitCredentialHelper.enable = false;
      programs.git.enable = true;
      kdn.development.git.enable = true;
      # programs.git.signing.key = "CDDFE1610327F6F7A693125698C23F71A188991B";
      programs.git.signing.key = null;
      programs.git.signing.signByDefault = true;
      programs.git.userName = systemUser.description;
      programs.git.userEmail = "gpg@kdn.im";
      programs.git.ignores = [ (builtins.readFile ./.gitignore) ];
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

        credential."https://gitlab.com/signicat/".username = "signicat-krznaz";
        url."https://gitlab.com/signicat/".insteadOf = "git@gitlab.com:signicat/";
      };
    })
    (lib.mkIf hasGUI {
      # KDE Connect
      services.kdeconnect.enable = true;
      services.kdeconnect.indicator = true;
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
    (lib.mkIf hasGUI {
      # see https://github.com/nix-community/home-manager/issues/2104#issuecomment-861676751
      home.file."${nc.rel}/images/screenshots/.keep".source = builtins.toFile "keep" "";
      services.flameshot.settings.General.savePath = "${nc.abs}/images/screenshots";
      xdg.configFile."gsimplecal/config".source = ./gsimplecal/config;

      services.nextcloud-client.enable = true;
      services.nextcloud-client.startInBackground = true;
      systemd.user.services.nextcloud-client.Service = {
        Restart = "on-failure";
        RestartSec = 3;
      };

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
        Install.WantedBy = [ "graphical-session.target" ];
      };
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
        kdn.ente-photos-desktop

        spotifywm

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
        haruna
        shotwell
        gimp

        qrencode
        #cobang # QR code scanner # 2024-01-23: dependency failed to build
        zbar # QR/BAR CODE READER: `zbarimg /path/to.img
        imagemagick

        logseq
        kdn.klog-time-tracker
        kdn.klg
        kdn.ss-util
        ungoogled-chromium
        rambox # browser/multi workspace
        drawio
        plantuml

        element-desktop
        signal-desktop
        slack
        zoom-us
        nextcloud-client

        deluge

        httpie-desktop
      ];
    })
    ({
      programs.helix.enable = true;
      programs.helix.settings.theme = "darcula-solid";
      stylix.targets.helix.enable = false;
    })
  ]);
}
