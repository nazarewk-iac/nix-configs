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

    programs.sway.extraSessionCommands = ''
      . /etc/set-environment
    '';

    # because tray opens up too late https://github.com/Alexays/Waybar/issues/483
    environment.etc."sway/config.d/systemd-init-00.conf".source =
      let
        init = pkgs.writeScriptBin "_sway-init" ''
          #! ${pkgs.bash}/bin/bash
          set -xeEuo pipefail
          interval=2
          until systemctl --user show-environment | grep WAYLAND_DISPLAY ; do
           sleep "$interval"
          done
          until pgrep -fu $UID polkit-gnome-authentication-agent-1 ; do sleep "$interval"; done
          until pgrep -fu $UID waybar && sleep 3 ; do sleep "$interval"; done
          systemctl --user start sway-session.target
          # systemd-notify --ready || true
          test "$#" -lt 1 || exec "$@"
        '';
      in
      pkgs.writeText "sway-systemd-init.conf" ''
        exec ${init}/bin/_sway-init
      '';
  };
}
