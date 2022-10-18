{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.kdn.xfce.base;
in
{
  options.kdn.xfce.base = {
    enable = mkEnableOption "XFCE4 base setup";
    enableDesktop = mkEnableOption "enable XFCE desktop?";
  };

  config = lib.mkMerge [
    (mkIf cfg.enable {
      services.xserver.desktopManager.xfce = {
        enable = true;
        noDesktop = !cfg.enableDesktop;
        enableXfwm = cfg.enableDesktop;
        enableScreensaver = cfg.enableDesktop;
      };
      services.tumbler.enable = true; # Thumbnail support for images

      programs.thunar.enable = true;
      programs.thunar.plugins = with pkgs.xfce; [
        thunar-archive-plugin
        thunar-volman
        thunar-media-tags-plugin
      ];


      environment.gnome.excludePackages = with pkgs.gnome; [
        gnome-terminal
        nautilus
        sushi
      ];
    })
  ];
}
