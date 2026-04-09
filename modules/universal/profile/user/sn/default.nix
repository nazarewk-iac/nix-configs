{
  lib,
  config,
  pkgs,
  kdnConfig,
  ...
}:
let
  cfg = config.kdn.profile.user.sn;
in
{
  options.kdn.profile.user.sn = {
    enable = lib.mkEnableOption "enable sn's user profiles";
    osConfig = lib.mkOption { default = { }; };
  };

  config = lib.mkMerge [
    (kdnConfig.util.ifHM (
      lib.mkIf cfg.enable (
        lib.mkMerge [
          {
            kdn.locale = {
              primary = "pl_PL.UTF-8";
              time = "pl_PL.UTF-8";
            };
          }
          {
            stylix.image = pkgs.fetchurl {
              # non-expiring share link
              url = "https://nc.nazarewk.pw/s/q63pjY9H93faf5t/download/lake-view-with-light-blue-water-a6cnqa1pki4g69jt.jpg";
              sha256 = "sha256-0Dyc9Kj9IkStIJDXw9zlEFHqc2Q5WruPSk/KapM7KgM=";
            };
            stylix.polarity = "light";
            stylix.base16Scheme = "${pkgs.base16-schemes}/share/themes/standardized-light.yaml";
          }
          {
            home.packages = with pkgs; [
              vlc
            ];

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

            services.flameshot.settings.General.savePath = "${config.home.homeDirectory}/Downloads/screenshots";

            xdg.mime.enable = true;
            xdg.mimeApps.enable = true;
            xdg.mimeApps.associations.added = { };
            xdg.mimeApps.defaultApplications =
              let
                rss = [ "brave-browser.desktop" ];
                ipfs = [ "brave-browser.desktop" ];
                browser = [ "firefox.desktop" ];
                pdf = [ "org.gnome.Evince.desktop" ];
                fileManager = [ "thunar.desktop" ];
                vectorImages = [ "org.gnome.eog.desktop" ];
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
                "application/xhtml+xml" = browser;
                "application/xhtml_xml" = browser;
                "image/svg+xml" = vectorImages;
                "inode/directory" = fileManager;
                "text/html" = browser;
                "text/xml" = browser;
                "x-scheme-handler/chrome" = browser;
                "x-scheme-handler/http" = browser;
                "x-scheme-handler/https" = browser;
                "x-scheme-handler/ipfs" = ipfs;
                "x-scheme-handler/ipns" = ipfs;
              };
          }
        ]
      )
    ))
    (kdnConfig.util.ifTypes [ "nixos" ] (
      lib.mkIf cfg.enable {
        kdn.hw.yubikey.appId = "pam://kdn";
        nix.settings.allowed-users = [ "sn" ];
        kdn.programs.atuin.users = [ "sn" ];
        kdn.disks.users.sn.homeLocation = "usr/data";
        users.users.sn.initialHashedPassword = "$y$j9T$WGU0Qrlm0.jq7Y4QfyVYC0$HiYyLZMDX8M/A7WNshB5PjtZEGufQ.Qa93FY4WIlcw8";
        users.users.sn = {
          uid = 48378;
          description = "Staś";
          isNormalUser = true;
          createHome = true; # makes sure ZFS mountpoints are properly owned?
          extraGroups = lib.filter (group: lib.hasAttr group config.users.groups) [
            "audio"
            "dialout"
            "lp"
            "lpadmin"
            "mlocate"
            "networkmanager"
            "pipewire"
            "plugdev"
            "power"
            "scanner"
            "tty"
            "video"
          ];
        };
        home-manager.users.sn = {
          kdn.profile.user.sn = {
            enable = true;
            osConfig = config.users.users.sn;
          };
        };
      }
    ))
  ];
}
