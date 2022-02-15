{ lib, pkgs, config, flakeInputs, ... }:
with lib;
let
  cfg = config.nazarewk.desktop.base;
in {
  options.nazarewk.desktop.base = {
    enable = mkEnableOption "Desktop base setup";
  };

  config = mkIf cfg.enable {
    nixpkgs.overlays = [
      flakeInputs.nixpkgs-wayland.overlay
    ];

    fonts.fonts = with pkgs; [
      cantarell-fonts
      font-awesome
      nerdfonts
      noto-fonts
      noto-fonts-emoji
      noto-fonts-emoji-blob-bin
      noto-fonts-extra
    ];

    environment.systemPackages = with pkgs; [
      qt5.qtwayland
      qt5Full

      xorg.xeyes
      xlibs.xhost

      # audio
      libopenaptx
      libfreeaptx
      pulseaudio
    ];
  };
}
