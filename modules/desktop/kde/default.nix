{ lib, pkgs, config, inputs, ... }:
let
  cfg = config.kdn.desktop.kde;
in
{
  options.kdn.desktop.kde = {
    enable = lib.mkEnableOption "KDE Plasma desktop setup";
  };

  config = lib.mkIf cfg.enable {
    services.xserver.displayManager.defaultSession = "plasmawayland";
    # conflicts with seahorse
    programs.ssh.askPassword = "${pkgs.libsForQt5.ksshaskpass.out}/bin/ksshaskpass";

    environment.systemPackages = with pkgs; [
    ];

    services.xserver.enable = true;
    services.xserver.displayManager.sddm.enable = true;
    services.xserver.desktopManager.plasma5 = {
      enable = true;
      phononBackend = "vlc";
      useQtScaling = true;
    };
  };
}
