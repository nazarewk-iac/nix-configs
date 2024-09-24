{ lib, pkgs, config, ... }:
let
  cfg = config.kdn.services.syncthing;
in
{
  options.kdn.services.syncthing = {
    enable = lib.mkEnableOption "Syncthing file synchronization";
  };

  config = lib.mkIf cfg.enable {
    services.syncthing.enable = true;
    services.syncthing.extraOptions = [
      # see https://docs.syncthing.net/users/syncthing.html
      "--config=${config.xdg.configHome}/syncthing"
      "--data=${config.xdg.dataHome}/syncthing"
      "--auditfile=--"
      "--gui-address=127.0.0.1:8384"
    ];
    services.syncthing.tray.enable = false;
    home.persistence."usr/data".directories = [
      ".local/share/syncthing"
    ];
    home.persistence."usr/config".directories = [
      ".config/syncthing"
    ];

    systemd.user.services.syncthing = {
      Unit.After = [ "paths.target" ];
    };
    home.packages = with pkgs; [
      stc-cli
    ];
  };
}
