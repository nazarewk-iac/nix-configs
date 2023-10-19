{ lib, pkgs, config, inputs, ... }:
let
  cfg = config.kdn.desktop.kde;
in
{
  options.kdn.desktop.kde = {
    enable = lib.mkEnableOption "KDE Plasma desktop setup";
  };

  config = lib.mkIf cfg.enable {
    home-manager.sharedModules = [{
      kdn.desktop.kde.enable = cfg.enable;
    }];
    services.xserver.displayManager.defaultSession = "plasmawayland";
    # conflicts with seahorse https://github.com/NixOS/nixpkgs/blob/898cb2064b6e98b8c5499f37e81adbdf2925f7c5/nixos/modules/programs/seahorse.nix#L34
    programs.ssh.askPassword = "${pkgs.libsForQt5.ksshaskpass.out}/bin/ksshaskpass";

    services.gnome.gnome-keyring.enable = lib.mkForce false;

    environment.systemPackages = (with pkgs;[
      latte-dock
    ]) ++ (with pkgs.libsForQt5; [
      kleopatra
      #bismuth  # bismuth is abandoned (no update for a year)
    ]);

    services.xserver.enable = true;
    services.xserver.displayManager.sddm.enable = true;
    services.xserver.displayManager.sddm.wayland.enable = true;
    services.xserver.desktopManager.plasma5 = {
      enable = true;
      phononBackend = "vlc";
      useQtScaling = true;
    };
    programs.dconf.enable = true;
  };
}
