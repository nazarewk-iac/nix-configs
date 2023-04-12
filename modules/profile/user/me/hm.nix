{ config, pkgs, lib, nixosConfig, ... }@arguments:
let
  cfg = config.kdn.profile.user.me;
  systemUser = cfg.nixosConfig;
  hasGUI = config.kdn.headless.enableGUI;
  hasWorkstation = nixosConfig.kdn.profile.machine.workstation.enable;

  git-credential-keyring =
    let
      wrapped = pkgs.writeShellApplication {
        name = "git-credential-keyring-wrapped";
        runtimeInputs = [ pkgs.kdn.git-credential-keyring ];
        text = ''
          export PYTHON_KEYRING_BACKEND="keyring_pass.PasswordStoreBackend"
          export KEYRING_PROPERTY_PASS_BINARY="${pkgs.pass}/bin/pass"
          git-credential-keyring "$@"
        '';
      };
    in
    "${wrapped}/bin/git-credential-keyring-wrapped";
in
{
  options.kdn.profile.user.me = {
    nixosConfig = lib.mkOption { default = { }; };
  };
  config = lib.mkIf (cfg != { }) (lib.mkMerge [
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

      kdn.services.syncthing.enable = true;
    }
    (lib.mkIf hasWorkstation {
      programs.gh.enable = false;
      programs.gh.enableGitCredentialHelper = false;
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

        credential."https://bitbucket.org/pakpobox".username = "kdn-alfred24";
      };
    })
    (lib.mkIf hasGUI {
      services.flameshot.settings.General.savePath = "${config.home.homeDirectory}/Downloads/screenshots";
      xdg.configFile."gsimplecal/config".source = ./gsimplecal/config;

      services.kdeconnect.enable = true;
      services.kdeconnect.indicator = true;

      xdg.mime.enable = true;
      xdg.mimeApps.enable = true;
      xdg.mimeApps.associations.added = { };
      xdg.mimeApps.defaultApplications =
        let
          rss = [ "brave-browser.desktop" ];
          ipfs = [ "brave-browser.desktop" ];
          browser = [ "firefox.desktop" "brave-browser.desktop" ];
          pdf = [ "org.gnome.Evince.desktop" ];
          fileManager = [ "thunar.desktop" ];
          remmina = [ "org.remmina.Remmina.desktop" ];
          teams = [ "teams.desktop" ];
          ide = [ "idea-ultimate.desktop" ];
          vectorImages = [ "org.gnome.eog.desktop" ];
          terminal = [ "foot.desktop" ];
        in
        {
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
    })
    (lib.mkIf (hasWorkstation && hasGUI) {
      programs.password-store.settings = {
        PASSWORD_STORE_DIR = "${config.home.homeDirectory}/Nextcloud/drag0nius@nc.nazarewk.pw/important/password-store";
      };

      home.packages = with pkgs; let
        launch = (lib.kdn.shell.writeShellScript pkgs (./bin + "/kdn-launch.sh") {
          runtimeInputs = with pkgs; [
            coreutils
            procps
            libnotify
            sway
            jq

            nextcloud-client
            pass
            drag0nius_kdbx
            keepass # must come from NixOS-level override

            flameshot
            blueman

            firefox
            jetbrains.idea-ultimate

            element-desktop
            signal-desktop
            slack
            teams
            kdn.rambox
          ];
        });
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
        launch
        drag0nius_kdbx

        flameshot
        vlc
        haruna
        evince
        xfce.ristretto
        xfce.exo
        xfce.xfconf
        shotwell
        gimp

        qrencode
        cobang # QR code scanner
        imagemagick

        logseq
        kdn.klog-time-tracker
        kdn.klg
        dex # A program to generate and execute DesktopEntry files of the Application type
        brave
        kdn.rambox # browser/multi workspace
        drawio
        plantuml

        element-desktop
        signal-desktop
        slack
        teams
        discord
        zoom-us
        nextcloud-client

        #transmission-qt
        deluge
        megatools
      ];
    })
  ]);
}
