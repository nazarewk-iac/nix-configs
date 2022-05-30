{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.nazarewk.sway.gdm;
in
{
  options.nazarewk.sway.gdm = {
    enable = mkEnableOption "running Sway WM in GDM";
  };

  config = mkIf cfg.enable {
    nazarewk.sway.base.enable = true;

    services.xserver.enable = true;
    services.xserver.displayManager.defaultSession = "sway";
    services.xserver.displayManager.gdm.enable = true;
    services.xserver.libinput.enable = true;

    nazarewk.sway.base.initScripts.systemd = {
      "01-wait-gdm-environment" = ''
        #! ${pkgs.bash}/bin/bash
        set -xeEuo pipefail
        test -n "''${GDMSESSION:-}" || exit 0

        until systemctl --user show-environment | grep WAYLAND_DISPLAY ; do
         sleep 2
        done
      '';
    };
  };
}
