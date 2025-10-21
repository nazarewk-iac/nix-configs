{
  config,
  pkgs,
  lib,
  ...
}@arguments:
let
  cfg = config.kdn.profile.user.sn;
  systemUser = cfg.osConfig;
in
{
  options.kdn.profile.user.sn = {
    enable = lib.mkEnableOption "sn account setup";

    osConfig = lib.mkOption { default = { }; };
  };
  config = lib.mkIf cfg.enable (
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
            stripComments = lib.filter (
              line: (builtins.match "\w*" line) == null && (builtins.match "\w*#.*" line) == null
            );
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
  );
}
