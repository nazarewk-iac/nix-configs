{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.nazarewk.desktop.base;
in {
  options.nazarewk.desktop.base = {
    enable = mkEnableOption "Desktop base setup";
  };

  config = mkIf cfg.enable {
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
