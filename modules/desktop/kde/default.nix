{ lib, pkgs, config, inputs, ... }:
let
  cfg = config.kdn.desktop.kde;
in
{
  options.kdn.desktop.kde = {
    enable = lib.mkEnableOption "KDE Plasma desktop setup";
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      home-manager.sharedModules = [{ kdn.desktop.kde.enable = cfg.enable; }];
      services.xserver.displayManager.defaultSession = "plasmawayland";
      # conflicts with seahorse https://github.com/NixOS/nixpkgs/blob/898cb2064b6e98b8c5499f37e81adbdf2925f7c5/nixos/modules/programs/seahorse.nix#L34
      programs.ssh.askPassword = "${pkgs.libsForQt5.ksshaskpass.out}/bin/ksshaskpass";

      services.gnome.gnome-keyring.enable = lib.mkForce false;

      environment.systemPackages = (with pkgs;[
        latte-dock
      ]) ++ (with pkgs.libsForQt5; [
        kleopatra # GPG management
        okular # pdf viewer
        ark # archive manager
        gwenview # image viewer & editor
        pix # image gallery viewer
        # kontact # doesn't work, see https://github.com/NixOS/nixpkgs/issues/190658
      ]);

      services.xserver.enable = true;
      services.xserver.displayManager.sddm.enable = true;
      services.xserver.displayManager.sddm.wayland.enable = true;
      services.xserver.desktopManager.plasma5.enable = true;
      programs.dconf.enable = true;
    }
    # styling
    {
      services.xserver.desktopManager.plasma5 = {
        phononBackend = "vlc";
        useQtScaling = true;
      };

      qt.enable = true;
      qt.style = "breeze";
      qt.platformTheme = "kde";
    }
    {
      # see https://discourse.nixos.org/t/kde-widgets-look-off-on-a-freshly-installed-nixos/13098
      environment.systemPackages = (with pkgs.libsForQt5; [
        qqc2-breeze-style
        qqc2-desktop-style
      ]);
      environment.sessionVariables.QT_QUICK_CONTROLS_STYLE = "org.kde.desktop";
    }
  ]);
}
