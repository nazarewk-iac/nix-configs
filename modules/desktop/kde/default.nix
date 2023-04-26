{ lib, pkgs, config, inputs, ... }:
let
  cfg = config.kdn.desktop.kde;
in
{
  options.kdn.desktop.kde = {
    enable = lib.mkEnableOption "KDE Plasma desktop setup";
  };

  config = lib.mkIf cfg.enable {
    services.xserver.displayManager.defaultSession = lib.mkDefault "plasma";

    environment.systemPackages = with pkgs; [
    ];

    services.xserver.enable = true;
    services.xserver.desktopManager.plasma5 = {
      enable = true;
      phononBackend = "vlc";
      useQtScaling = true;
    };
  };
}
