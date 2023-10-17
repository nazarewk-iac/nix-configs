{ config, pkgs, lib, nixosConfig, ... }@arguments:
let
  cfg = config.kdn.profile.user.kdn;
  systemUser = cfg.nixosConfig;
  hasGUI = config.kdn.headless.enableGUI;
  hasSway = config.kdn.sway.base.enable;
  hasWorkstation = nixosConfig.kdn.profile.machine.workstation.enable;

  git-credential-keyring =
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
in
{
  options.kdn.profile.user.kdn = {
    enable = lib.mkEnableOption "me (kdn) account setup";

    nixosConfig = lib.mkOption { default = { }; };
  };
  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      home.stateVersion = "22.11";
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
        credential.helper = git-credential-keyring;

        # use it separately because `gh` cli wants to write to ~/.config/gh/config.yml
        credential."https://github.com".helper = "${pkgs.gh}/bin/gh auth git-credential";
        url."https://github.com/".insteadOf = "git@github.com:";

        credential."https://gitlab.com/signicat/".username = "signicat-krznaz";
        url."https://gitlab.com/signicat/".insteadOf = "git@gitlab.com:signicat/";

        credential."https://gitlab.electronicid.eu/".username = "krznaz";
        url."https://gitlab.electronicid.eu/".insteadOf = "git@gitlab.electronicid.eu:";
      };
    })
    (lib.mkIf hasGUI {
      services.flameshot.settings.General.savePath = "${config.home.homeDirectory}/Downloads/screenshots";
      xdg.configFile."gsimplecal/config".source = ./gsimplecal/config;

      services.nextcloud-client.enable = true;
      services.nextcloud-client.startInBackground = true;

      services.kdeconnect.enable = true;
      services.kdeconnect.indicator = true;

      xdg.mime.enable = true;
      xdg.mimeApps.enable = true;
      xdg.mimeApps.associations.added = { };
      xdg.mimeApps.defaultApplications =
        let
          brave = [ "brave-browser.desktop" ];
          browser = [ "uri-to-clipboard.desktop" "firefox.desktop" ] ++ brave;
          fileManager = [ "pcmanfm-qt.desktop" ];
          ide = [ "idea-ultimate.desktop" ];
          ipfs = brave;
          pdf = [ "org.kde.okular.desktop" ];
          remmina = [ "org.remmina.Remmina.desktop" ];
          rss = brave;
          teams = brave;
          terminal = [ "foot.desktop" ];
          vectorImages = [ "org.gnome.eog.desktop" ];
        in
        lib.mkForce {
          "application/pdf" = pdf;
          "application/rdf+xml" = rss;
          "application/rss+xml" = rss;
          "application/x-extension-htm" = browser;
          "application/x-extension-html" = browser;
          "application/x-extension-shtml" = browser;
          "application/x-extension-xht" = browser;
          "application/x-extension-xhtml" = browser;
          "application/x-gnome-saved-search" = fileManager;
          "application/x-remmina" = remmina;
          "application/xhtml+xml" = browser;
          "application/xhtml_xml" = browser;
          "image/svg+xml" = vectorImages;
          "inode/directory" = fileManager;
          "text/html" = browser;
          "text/plain" = ide;
          "text/xml" = browser;
          "x-scheme-handler/chrome" = browser;
          "x-scheme-handler/http" = browser;
          "x-scheme-handler/https" = browser;
          "x-scheme-handler/ipfs" = ipfs;
          "x-scheme-handler/ipns" = ipfs;
          "x-scheme-handler/msteams" = teams;
          "x-scheme-handler/rdp" = remmina;
          "x-scheme-handler/remmina" = remmina;
          "x-scheme-handler/spice" = remmina;
          # TODO: set thunar terminal https://github.com/chmln/handlr/issues/62
          "x-scheme-handler/terminal" = terminal;
          "x-scheme-handler/vnc" = remmina;
        };

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
          noDisplay = true;
          genericName = "uri-to-clipboard";
          exec = "${bin} %U";
          categories = [ "Network" "WebBrowser" ];
        };

    })
    (lib.mkIf (hasSway) {
      systemd.user.services.nextcloud-client.Unit = {
        Requires = lib.mkForce [ "pass-secret-service.service" "kdn-sway-envs.target" ];
        After = [ "kdn-sway-envs.target" "tray.target" ];
        PartOf = [ "kdn-sway-session.target" ];
      };
      systemd.user.services.nextcloud-client.Install = {
        WantedBy = [ "kdn-sway-session.target" ];
      };
      systemd.user.services.kdeconnect.Unit = {
        Requires = [ "kdn-sway-envs.target" ];
        After = [ "kdn-sway-envs.target" ];
        PartOf = [ "kdn-sway-session.target" ];
      };
      systemd.user.services.kdeconnect-indicator.Unit = {
        Requires = [ "kdn-sway-envs.target" "kdeconnect.service" ];
        After = [ "tray.target" "kdn-sway-envs.target" "kdeconnect.service" ];
        PartOf = [ "kdn-sway-session.target" ];
      };
      home.packages = with pkgs; let
        launch = (lib.kdn.shell.writeShellScript pkgs (./bin + "/kdn-launch.sh") {
          runtimeInputs = with pkgs; [
            coreutils
            procps
            libnotify
            sway
            jq

            pass
            drag0nius_kdbx
            keepass # must come from NixOS-level override

            firefox

            element-desktop
            signal-desktop
            slack
            rambox
          ];
        });
      in
      [
        launch
      ];
    })
    (lib.mkIf (hasWorkstation && hasGUI) {
      home.packages = with pkgs; let
        drag0nius_kdbx =
          (pkgs.writeShellApplication {
            name = "keepass-drag0nius.kdbx";
            runtimeInputs = [ pkgs.pass pkgs.keepass ];
            text = ''
              cmd_start () {
                  local db_path="$HOME/Nextcloud/drag0nius@nc.nazarewk.pw/Dropbox import/Apps/KeeAnywhere/drag0nius.kdbx"
                  pass KeePass/drag0nius.kdbx | keepass "$db_path" -pw-stdin
              }

              "cmd_''${1:-start}" "''${@:2}"
            '';
          });
      in
      [
        keepass
        drag0nius_kdbx

        flameshot
        vlc
        haruna
        libsForQt5.okular # pdf viewer
        libsForQt5.ark # archive manager
        libsForQt5.gwenview # image viewer & editor
        libsForQt5.pix # image gallery viewer
        shotwell
        gimp

        qrencode
        cobang # QR code scanner
        zbar # QR/BAR CODE READER: `zbarimg /path/to.img
        imagemagick

        logseq
        kdn.klog-time-tracker
        kdn.klg
        kdn.ss-util
        dex # A program to generate and execute DesktopEntry files of the Application type
        brave
        rambox # browser/multi workspace
        drawio
        plantuml

        element-desktop
        signal-desktop
        slack
        discord
        zoom-us
        nextcloud-client

        #transmission-qt
        deluge
      ];
    })
  ]);
}
