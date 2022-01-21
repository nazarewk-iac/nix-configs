{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.nazarewk.sway.systemd;
  mandatoryEnvs = toString [
    "DISPLAY"
    "WAYLAND_DISPLAY"
    "SWAYSOCK"
    "XDG_CURRENT_DESKTOP"
  ];
in {
  options.nazarewk.sway.systemd = {
    enable = mkEnableOption "running Sway WM as a systemd service";
  };

  config = mkIf cfg.enable {
    nazarewk.sway.base.enable = true;

    systemd.user.services.sway = {
      description = "Sway - Wayland window manager";
      documentation = [ "man:sway(5)" ];
      bindsTo = [ "graphical-session.target" ];
      wants = [ "graphical-session-pre.target" ];
      after = [ "graphical-session-pre.target" ];
      # We explicitly unset PATH here, as we want it to be set by
      # systemctl --user import-environment in startsway
      environment.PATH = lib.mkForce null;
      serviceConfig = {
        Type = "notify";
        # NotifyAccess = "exec";
        NotifyAccess = "all";
        # wrapper already contains dbus-session-run
        ExecStart = "/run/current-system/sw/bin/sway";
        ExecStopPost = "systemctl --user unset-environment ${mandatoryEnvs}";
        Restart = "no";
        RestartSec = 1;
        TimeoutStopSec = 60;
      };
    };

    # because tray opens up too late https://github.com/Alexays/Waybar/issues/483
    environment.etc."sway/config.d/systemd-init-00.conf".source = let
      init = pkgs.writeScriptBin "_sway-init" ''
        #! ${pkgs.bash}/bin/bash
        set -xeEuo pipefail
        interval=2
        until systemctl --user show-environment | grep WAYLAND_DISPLAY ; do
          sleep "$interval"
          dbus-update-activation-environment --systemd --all --verbose
        done
        until pgrep -fu $UID polkit-gnome-authentication-agent-1 ; do sleep "$interval"; done
        until pgrep -fu $UID waybar && sleep 3 ; do sleep "$interval"; done
        systemctl --user start sway-session.target
        systemd-notify --ready || true
        test "$#" -lt 1 || exec "$@"
      '';
      in pkgs.writeText "sway-systemd-init.conf" ''
        exec ${init}/bin/_sway-init
      '';

    programs.sway.extraPackages = with pkgs; [
      (pkgs.writeScriptBin "startsway" ''
        #! ${pkgs.bash}/bin/bash
        set -xeEuo pipefail
        systemctl --user import-environment $(${pkgs.jq}/bin/jq -rn 'env | keys[]')
        exec systemctl --user start sway.service
      '')
    ];
  };
}
