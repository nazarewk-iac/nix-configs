{ lib, pkgs, config, inputs, ... }:
with lib;
let
  cfg = config.kdn.desktop.base;
in
{
  options.kdn.desktop.base = {
    enable = lib.mkEnableOption "Desktop base setup";

    enableWlrootsPatch = mkEnableOption "patched wlroots";

    nixpkgs-wayland = {
      enableFullOverlay = mkEnableOption "use nixpkgs-wayland overlay for bleeding-edge wayland packages";
    };
  };

  config = lib.mkIf cfg.enable {
    nixpkgs.overlays = (if !cfg.nixpkgs-wayland.enableFullOverlay then [ ] else [
      inputs.nixpkgs-wayland.overlay
    ]) ++ (if !cfg.enableWlrootsPatch then [ ] else [
      (final: prev: {
        wlroots = prev.wlroots.overrideAttrs (old: {
          src = prev.fetchFromGitLab {
            domain = "gitlab.freedesktop.org";
            owner = "wlroots";
            repo = "wlroots";
            # report: https://github.com/swaywm/sway/issues/6856
            # overriden version: https://gitlab.freedesktop.org/wlroots/wlroots/-/merge_requests/3469/commits
            rev = "15008750db82115fbdcf77d1fccbde9a91d70a06";
            sha256 = "sha256-T3LhUaczQVp0mj/vKpxRb7PLwZk0iEsejOqSWtQMw8k=";
          };
        });
      })
    ]);

    fonts.fonts = with pkgs; [
      cantarell-fonts
      font-awesome
      nerdfonts
      noto-fonts
      noto-fonts-emoji
      noto-fonts-emoji-blob-bin
      noto-fonts-extra
      anonymousPro
    ];

    hardware.uinput.enable = true;
    kdn.programs.ydotool.enable = true;
    programs.dconf.enable = true;
    programs.evince.enable = true;
    programs.file-roller.enable = true;
    security.polkit.enable = true;
    services.accounts-daemon.enable = true;
    services.dleyna-renderer.enable = true;
    services.dleyna-server.enable = true;
    services.gvfs.enable = true;
    services.power-profiles-daemon.enable = true;
    services.udisks2.enable = true;
    services.upower.enable = config.powerManagement.enable;
    services.xserver.updateDbusEnvironment = true;
    xdg.icons.enable = true;
    xdg.mime.enable = true;

    environment.systemPackages = with pkgs; [
      qt5.qtwayland
      qt5Full

      xorg.xeyes
      xorg.xhost

      # audio
      libopenaptx
      libfreeaptx
      pulseaudio

      # graphics
      libva-utils

      # tools
      brightnessctl
      gsettings-desktop-schemas
      gtk-engine-murrine
      gtk_engines
      lxappearance
      xsettingsd

      # debugging
      evtest # listens for /dev/event* device events (eg: keyboard keys, function keys etc)
      libinput
      v4l-utils
      wev # wayland event viewer
      wshowkeys # display pressed keys

      # themes
      hicolor-icon-theme # nm-applet, see https://github.com/NixOS/nixpkgs/issues/32730
      gnome-icon-theme # nm-applet, see https://github.com/NixOS/nixpkgs/issues/43836#issuecomment-419217138
      glib # gsettings
      sound-theme-freedesktop
    ];

    qt = {
      enable = true;
      platformTheme = "gtk2";
      style = "gtk2";
    };
  };
}
