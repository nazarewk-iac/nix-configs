{
  osConfig,
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.kdn.desktop.kde;
in
{
  options.kdn.desktop.kde = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      apply = value: value && config.kdn.desktop.enable;
    };
  };
  config = lib.mkIf cfg.enable {
    # fix something is reformatting the fontconfigs (removing empty lines) when running KDE Plasma
    xdg.configFile."fontconfig/conf.d/10-hm-fonts.conf".force = true;
    services.gnome-keyring.enable = lib.mkForce false;
  };
}
