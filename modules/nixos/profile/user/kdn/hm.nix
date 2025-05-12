{
  config,
  pkgs,
  lib,
  osConfig,
  ...
} @ arguments: let
  cfg = config.kdn.profile.user.kdn;
  hasSway = config.kdn.desktop.sway.enable;
  hasWorkstation = osConfig.kdn.profile.machine.workstation.enable;

  nc.rel = "Nextcloud/drag0nius@nc.nazarewk.pw";
  nc.abs = "${config.home.homeDirectory}/${nc.rel}";
in {
  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      home.file.".ssh/config.d/kdn.config".source = config.lib.file.mkOutOfStoreSymlink "/run/configs/networking/ssh_config/kdn";
    }
    (lib.mkIf hasWorkstation {
      kdn.hw.disks.persist."usr/data".directories = [
        "dev"
      ];

      kdn.services.syncthing.enable = true;
      kdn.programs.weechat.enable = true;
    })
    (lib.mkIf config.kdn.programs.firefox.enable (lib.mkMerge [
      {
        # Firefox

        # don't search/expand single-word searchbars
        programs.firefox.policies.GoToIntranetSiteForSingleWordEntryInAddressBar = true;

        kdn.programs.firefox.profileNames = ["kdn" "jp"];
        programs.firefox.profiles.jp.id = 1;
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
        kdn.programs.firefox.profileNames = ["bn"];
        programs.firefox.profiles.bn = {
          id = 2;
        };
      }
    ]))
    (lib.mkIf config.kdn.desktop.enable {
      # see https://github.com/nix-community/home-manager/issues/2104#issuecomment-861676751
      home.file."${nc.rel}/images/screenshots/.keep".source = builtins.toFile "keep" "";
      services.flameshot.settings.General.savePath = "${nc.abs}/images/screenshots";
      xdg.configFile."gsimplecal/config".source = ./gsimplecal/config;

      xdg.mime.enable = true;
      xdg.desktopEntries.uri-to-clipboard = let
        bin = pkgs.writeShellScript "uri-to-clipboard" ''
          set -eEuo pipefail

          url="$1"
          ${pkgs.libnotify}/bin/notify-send --expire-time=3000 "copied to clipboard" "$url"
          ${pkgs.wl-clipboard}/bin/wl-copy "$url"
        '';
      in {
        name = "Copy URI to clipboard";
        noDisplay = false;
        genericName = "uri-to-clipboard";
        exec = "${bin} %U";
        categories = ["Network" "WebBrowser"];
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
      kdn.programs.keepassxc.service.searchDirs = ["${nc.abs}/important/keepass"];
      kdn.programs.keepassxc.service.fileName = "drag0nius.kdbx";
    })
    (lib.mkIf (hasWorkstation && config.kdn.desktop.enable) {
      home.packages = with pkgs; [
        webex # meetings/screen sharing # TODO: didn't start the meeting on 2025-04-24
      ];
    })
    (lib.mkIf hasSway (import ./mimeapps.nix arguments).config)
    (lib.mkIf hasSway {
      systemd.user.services.keepassxc.Unit = {
        BindsTo = config.kdn.desktop.sway.systemd.secrets-service.service;
        Requires = [config.kdn.desktop.sway.systemd.envs.target];

        After = [config.kdn.desktop.sway.systemd.envs.target];
        PartOf = [config.wayland.systemd.target];
      };
      systemd.user.services.keepassxc.Install.WantedBy = [config.kdn.desktop.sway.systemd.secrets-service.service];

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
        PartOf = [config.wayland.systemd.target];
      };
      systemd.user.services.nextcloud-client.Install = {
        WantedBy = [config.wayland.systemd.target];
      };
      systemd.user.services.kdeconnect.Unit = {
        Requires = [config.kdn.desktop.sway.systemd.envs.target];
        After = [config.kdn.desktop.sway.systemd.envs.target];
        PartOf = [config.wayland.systemd.target];
      };
      systemd.user.services.kdeconnect-indicator.Unit = {
        Requires = [config.kdn.desktop.sway.systemd.envs.target "kdeconnect.service"];
        After = ["tray.target" config.kdn.desktop.sway.systemd.envs.target "kdeconnect.service"];
        PartOf = [config.wayland.systemd.target];
      };
    })
    (lib.mkIf hasWorkstation {
      home.packages = with pkgs; [
        pkgs.kdn.klog-time-tracker
        pkgs.kdn.klg
      ];
      xdg.configFile."klg/config.toml".source = config.lib.file.mkOutOfStoreSymlink "${nc.abs}/time-logs/klg/config.toml";
    })
    (lib.mkIf (hasWorkstation && config.kdn.desktop.enable) {
      home.packages = with pkgs; [
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
        ffsubsync
        haruna
        shotwell

        qrencode
        #cobang # QR code scanner # 2024-01-23: dependency failed to build
        zbar # QR/BAR CODE READER: `zbarimg /path/to.img
        imagemagick

        pkgs.kdn.ss-util
        drawio
        plantuml

        zoom-us
        nextcloud-client

        deluge

        httpie-desktop
      ];
    })
    (lib.mkIf (hasWorkstation && config.kdn.desktop.enable) {
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
      kdn.toolset.print-3d.enable = true;
    })
  ]);
}
