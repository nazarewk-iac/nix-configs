{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.nazarewk.sway.systemd;
  mandatoryEnvsString = toString [
    "DISPLAY"
    "WAYLAND_DISPLAY"
    "SWAYSOCK"
    "XDG_CURRENT_DESKTOP"
  ];
in
{
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
      environment.NAZAREWK_SWAY_SYSTEMD = "1";
      serviceConfig = {
        Type = "notify";
        # NotifyAccess = "exec";
        NotifyAccess = "all";
        # wrapper already contains dbus-session-run
        ExecStartPre = "systemctl --user unset-environment ${mandatoryEnvsString}";
        ExecStart = "/run/current-system/sw/bin/sway";
        ExecStopPost = "systemctl --user unset-environment ${mandatoryEnvsString}";
        Restart = "no";
        RestartSec = 1;
        TimeoutStopSec = 60;
      };
    };

    nazarewk.sway.base.initScripts.systemd = {
      "01-wait-systemd-environment" = ''
        #!${pkgs.bash}/bin/bash
        set -xEeuo pipefail
        test "''${NAZAREWK_SWAY_SYSTEMD:-}" = "1" || exit 0

        until systemctl --user show-environment | grep WAYLAND_DISPLAY ; do
          sleep 2
          dbus-update-activation-environment --systemd --all --verbose
        done
      '';
      "99-notify-systemd-service" = ''
        #!${pkgs.bash}/bin/bash
        set -xEeuo pipefail
        test "''${NAZAREWK_SWAY_SYSTEMD:-}" = "1" || exit 0

        systemd-notify --ready || true
      '';
    };

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
