{ lib, pkgs, config, ... }:
let
  cfg = config.kdn.sway.systemd;

  mandatoryEnvsString = toString [
    "DISPLAY"
    "WAYLAND_DISPLAY"
    "SWAYSOCK"
    "XDG_CURRENT_DESKTOP"
  ];

  startsway-headless = (pkgs.writeScriptBin "startsway-headless" ''
    #! ${pkgs.bash}/bin/bash
    set -xeEuo pipefail

    export WLR_BACKENDS=headless
    export WLR_LIBINPUT_NO_DEVICES=1
    export XDG_SESSION_TYPE=wayland

    ${startsway}/bin/startsway
  '');

  startsway = (pkgs.writeScriptBin "startsway" ''
    #! ${pkgs.bash}/bin/bash
    set -xeEuo pipefail

    ${systemctlClearEnv}/bin/systemctl-clear-env
    systemctl --user import-environment $(${pkgs.jq}/bin/jq -rn 'env | keys[]')
    exec systemctl --user start sway.service
  '');
  systemctlClearEnv = pkgs.writeShellApplication {
    name = "systemctl-clear-env";
    runtimeInputs = with pkgs; [ systemd jq ];
    text = ''
      # shellcheck disable=SC2046
      systemctl --user unset-environment $(systemctl --user show-environment -o json | jq -r 'keys[]')
    '';
  };
in
{
  options.kdn.sway.systemd = {
    enable = lib.mkEnableOption "running Sway WM as a systemd service";
  };

  config = lib.mkIf cfg.enable {
    kdn.sway.base.enable = true;

    systemd.user.services.sway = {
      description = "Sway - Wayland window manager";
      documentation = [ "man:sway(5)" ];
      bindsTo = [ "graphical-session.target" ];
      wants = [ "graphical-session-pre.target" ];
      after = [ "graphical-session-pre.target" ];
      # We explicitly unset PATH here, as we want it to be set by
      # systemctl --user import-environment in startsway
      environment.PATH = lib.mkForce null;
      environment.KDN_SWAY_SYSTEMD = "1";
      serviceConfig = {
        Type = "notify";
        # NotifyAccess = "exec";
        NotifyAccess = "all";
        ExecStart = "/run/current-system/sw/bin/sway";
        # TODO: prepare a diff of an environment maybe re-using direnv intead of using mandatoryEnvsString
        ExecStopPost = "${systemctlClearEnv}/bin/systemd-clear-env";
        Restart = "no";
        RestartSec = 1;
        TimeoutStopSec = 60;
      };
    };

    kdn.sway.base.initScripts.systemd = {
      "01-wait-systemd-environment" = ''
        #!${pkgs.bash}/bin/bash
        set -xEeuo pipefail
        test "''${KDN_SWAY_SYSTEMD:-}" = "1" || exit 0

        # do something if needed
      '';
      "99-notify-systemd-service" = ''
        #!${pkgs.bash}/bin/bash
        set -xEeuo pipefail
        test "''${KDN_SWAY_SYSTEMD:-}" = "1" || exit 0

        systemd-notify --ready || true
      '';
    };

    programs.sway.extraPackages = with pkgs; [
      systemctlClearEnv
      startsway
      startsway-headless
      seatd
    ];
  };
}
