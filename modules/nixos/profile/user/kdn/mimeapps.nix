{lib, ...}: let
  browsers.uri-to-clipboard = ["uri-to-clipboard.desktop"];

  browsers.chooser = ["software.Browsers.desktop"]; # https://github.com/Browsers-software/browsers
  browsers.chromium = ["chromium-browser.desktop"];
  browsers.firefox = ["firefox.desktop"];
  browsers.preferred =
    with browsers; chooser
    #++ uri-to-clipboard
    #++ firefox
    #++ chromium
    ;

  fileManager = ["nemo.desktop"];
  ide = ["idea-ultimate.desktop"];
  pdf = ["org.kde.okular.desktop"];
  remmina = ["org.remmina.Remmina.desktop"];
  rss = browsers.chromium;
  teams = browsers.chromium;
  terminal = ["foot.desktop"];
  vectorImages = ["org.gnome.eog.desktop"];
  videoPlayer = ["vlc.desktop" "org.kde.haruna.desktop"];
in {
  config = {
    # TODO: use `xdg.mimeApps.defaultApplicationPackages` where appropriate
    xdg.mimeApps.enable = true;
    xdg.mimeApps.associations.added = {};
    xdg.mimeApps.defaultApplications = {
      "application/pdf" = pdf;
      "application/rdf+xml" = rss;
      "application/rss+xml" = rss;
      "application/x-extension-htm" = browsers.preferred;
      "application/x-extension-html" = browsers.preferred;
      "application/x-extension-shtml" = browsers.preferred;
      "application/x-extension-xht" = browsers.preferred;
      "application/x-extension-xhtml" = browsers.preferred;
      "application/x-gnome-saved-search" = fileManager;
      "application/x-remmina" = remmina;
      "application/xhtml+xml" = browsers.preferred;
      "application/xhtml_xml" = browsers.preferred;
      "image/svg+xml" = vectorImages;
      "inode/directory" = fileManager;
      "text/html" = browsers.preferred;
      "text/plain" = ide;
      "text/xml" = browsers.preferred;

      "video/mp4" = videoPlayer; # MP4 files
      "video/x-matroska" = videoPlayer; # MKV files
      "video/x-msvideo" = videoPlayer; # AVI files
      "video/quicktime" = videoPlayer; # MOV files
      "video/x-flv" = videoPlayer; # FLV files
      "video/webm" = videoPlayer; # WebM files
      "video/mpeg" = videoPlayer; # MPEG files
      "video/ogg" = videoPlayer; # OGG video files
      "video/3gpp" = videoPlayer; # 3GP files
      "video/x-ms-wmv" = videoPlayer; # WMV files

      "x-scheme-handler/chrome" = browsers.preferred;
      "x-scheme-handler/http" = browsers.preferred;
      "x-scheme-handler/https" = browsers.preferred;
      "x-scheme-handler/msteams" = teams;
      "x-scheme-handler/rdp" = remmina;
      "x-scheme-handler/remmina" = remmina;
      "x-scheme-handler/spice" = remmina;
      "x-scheme-handler/terminal" = terminal;
      "x-scheme-handler/vnc" = remmina;
    };
  };
}
