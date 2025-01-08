{
  lib,
  pkgs,
  config,
  inputs,
  ...
}: let
  cfg = config.kdn.desktop.kde;
in {
  options.kdn.desktop.kde = {
    enable = lib.mkEnableOption "KDE Plasma desktop setup";
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      home-manager.sharedModules = [{kdn.desktop.kde.enable = cfg.enable;}];
      services.desktopManager.plasma6.enable = true;
      services.displayManager.defaultSession = "plasma";
    }
    {
      # conflicts with seahorse https://github.com/NixOS/nixpkgs/blob/898cb2064b6e98b8c5499f37e81adbdf2925f7c5/nixos/modules/programs/seahorse.nix#L34
      programs.ssh.askPassword = "${pkgs.kdePackages.ksshaskpass.out}/bin/ksshaskpass";
      services.gnome.gnome-keyring.enable = lib.mkForce false;
    }
    {
      qt.enable = true;
      qt.style = "breeze";
      qt.platformTheme = "kde";

      # see https://discourse.nixos.org/t/kde-widgets-look-off-on-a-freshly-installed-nixos/13098
      environment.systemPackages = with pkgs.kdePackages; [
        qqc2-breeze-style
        qqc2-desktop-style
      ];
      environment.sessionVariables.QT_QUICK_CONTROLS_STYLE = "org.kde.desktop";
    }
  ]);
}
