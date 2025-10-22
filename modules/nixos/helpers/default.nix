{
  lib,
  pkgs,
  config,
  ...
}: let
  waitFor = {
    name,
    cmd,
    deps,
    interval ? "1s",
    timeout ? 60,
  }: let
    script = pkgs.writeShellApplication {
      name = "wait-for-${name}";
      runtimeInputs = (with pkgs; [coreutils]) ++ deps;
      text = ''
        set -x

        TIMEOUT="''${TIMEOUT:-"${toString timeout}"}"
        INTERVAL="''${INTERVAL:-"${interval}"}"

        SECONDS=0
        until ${lib.escapeShellArgs cmd} "$@"; do
          if [ "$SECONDS" -ge "$TIMEOUT" ] ; then
            echo "Timed out..." >&2
            exit 1
          fi
          sleep "$INTERVAL"
        done
        echo "Success!" >&2
      '';
    };
  in "${script}/bin/wait-for-${name}";

  waitForUserTarget = waitFor {
    name = "systemd-user-unit";
    cmd = [
      "systemctl"
      "is-active"
      "--quiet"
      "--user"
    ];
    deps = with pkgs; [systemd];
  };

  waitForTarget = waitFor {
    name = "systemd-unit";
    cmd = [
      "systemctl"
      "is-active"
      "--quiet"
    ];
    deps = with pkgs; [systemd];
  };
in {
  options.kdn.helpers = lib.mkOption {
    readOnly = true;
    default = {inherit waitFor waitForUserTarget waitForTarget;};
  };

  config = {
    home-manager.sharedModules = [
      {
        options.kdn.helpers = lib.mkOption {
          readOnly = true;
          default = config.kdn.helpers;
        };
      }
    ];
  };
}
