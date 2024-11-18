{
  lib,
  pkgs,
  # required
  prefix ? "kdn-sway",
  serviceName ? "${prefix}.service",
  desktopSessionName ? prefix,
  ...
}: let
  scripts.start-headless = pkgs.writeShellApplication {
    name = "${prefix}-start-headless";
    text = ''
      export WLR_BACKENDS=headless
      export WLR_LIBINPUT_NO_DEVICES=1
      export XDG_SESSION_TYPE=wayland

      exec ${lib.meta.getExe scripts.start}
    '';
  };

  scripts.start = pkgs.writeShellApplication {
    name = "${prefix}-start";
    runtimeInputs = with pkgs; [systemd];
    text = ''
      ${lib.meta.getExe scripts.env-clear}
      ${lib.meta.getExe scripts.env-load}

      args=()
      IGNORE_ERROR=0
      ret_code=0

      while [[ $# -gt 0 ]]; do
        case "$1" in
          --ignore-error) IGNORE_ERROR=1 shift ;;
          *) args+=("$1") ; shift ;;
        esac
      done

      systemctl --user start ${serviceName} "''${args[@]}" || true
      systemctl --user status ${serviceName} || ret_code=$?
      test "$IGNORE_ERROR" == 0 || exit 0
      exit $ret_code
    '';
  };

  scripts.env-load = pkgs.writeShellApplication {
    name = "${prefix}-session-env-load";
    runtimeInputs = with pkgs; [dbus jq];
    text = ''
      envs=()
      keys=()
      for arg in "$@"; do
        if [[ "$arg" == *=* ]]; then
          envs+=("$arg")
        else
          keys+=("$arg")
        fi
      done
      if [[ "$#" == 0 ]]; then
        readarray -t keys < <(jq -rn 'env|keys[]')
      fi
      for key in "''${keys[@]}"; do
        envs+=("$key=''${!key}")
      done
      dbus-update-activation-environment --systemd "''${envs[@]}"
    '';
  };

  scripts.env-clear = pkgs.writeShellApplication {
    name = "${prefix}-session-env-clear";
    runtimeInputs = with pkgs; [dbus systemd jq];
    text = ''
      keys=("$@")
      if [[ "$#" == 0 ]]; then
        readarray -t keys < <(systemctl --user show-environment -o json | jq -r 'keys[]')
      fi
      set_empty=()
      for key in "''${keys[@]}"; do
        set_empty+=("$key=")
      done
      dbus-update-activation-environment "''${set_empty[@]}"
      systemctl --user unset-environment "''${keys[@]}"
    '';
  };
  scripts.env-wait = pkgs.writeShellApplication {
    name = "${prefix}-session-env-wait";
    runtimeInputs = with pkgs; [systemd jq];
    text = ''
      log() {
        test "$LOG" == 1 || return 0
        echo "$@" >&2
      }

      progress() {
        test "$PROGRESS" == 1 || return 0
        echo "$@" >&2
      }

      wait_for_env() {
        until systemctl --user show-environment | grep -q "$1" ; do
          progress "$1: still waiting..."
          sleep $((RANDOM % MAXWAIT))
        done
        local cur=$SECONDS
        log "$1: loaded $((cur - last )) seconds after previous variable ($cur seconds since script start)"
        last=$SECONDS
      }

      LOG=1
      PROGRESS=0
      SHOW=0
      SLEEP=0
      while [[ $# -gt 0 ]]; do
        case $1 in
          -s|--show) SHOW=1 ; shift ;;
          --no-log) LOG=0 ; shift ;;
          -p|--progress) PROGRESS=1 ; shift ;;
          --sleep) SLEEP=$2 ; shift 2 ;;
        esac
      done

      last=0
      MAXWAIT=2

      for var in WAYLAND_DISPLAY KDN_SWAY_SYSTEMD ; do
        wait_for_env "$var"
      done

      log "found all the variables after $SECONDS seconds."
      test "$SHOW" == 0 || ${lib.meta.getExe scripts.env-show}
      sleep "$SLEEP"
      log "wait script has finished"
    '';
  };

  scripts.env-show = pkgs.writeShellApplication {
    name = "${prefix}-session-env-show";
    runtimeInputs = with pkgs; [systemd jq];
    text = "systemctl --user show-environment --output=json | jq -S";
  };

  extra.desktop-entry = pkgs.writeTextFile {
    name = "${desktopSessionName}-wayland-session";
    destination = "/share/wayland-sessions/${desktopSessionName}.desktop";
    # TODO: this doesn't exit properly in SDDM
    text = ''
      [Desktop Entry]
      Name=${desktopSessionName}
      Comment=An i3-compatible Wayland compositor
      Exec=${lib.meta.getExe scripts.start} --wait --ignore-error
      Type=Application
    '';
  };
in
  (pkgs.symlinkJoin {
    name = "${prefix}-bundle";
    passthru.providedSessions = [desktopSessionName];
    paths = builtins.attrValues (scripts // extra);
  })
  // {exes = builtins.mapAttrs (n: pkg: lib.meta.getExe pkg) scripts;}
