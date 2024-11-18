{
  lib,
  pkgs,
  config,
  inputs,
  ...
}: let
  cfg = config.kdn.programs.ulauncher;
in {
  options.kdn.programs.ulauncher = {
    enable = lib.mkEnableOption "ulauncher";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.ulauncher6;
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [cfg.package];

    systemd.user.services.ulauncher = {
      # mostly taken from https://github.com/Ulauncher/Ulauncher/blob/v6/ulauncher.service
      Service = {
        BusName = "io.ulauncher.Ulauncher";
        Type = "dbus";
        Restart = "on-failure";
        RestartSec = 3;
        ExecStart = "${cfg.package}/bin/ulauncher --no-window";
      };
      Install = {
        WantedBy = ["graphical-session.target"];
      };
      Unit = {
        Description = "Ulauncher service";
        Documentation = "https://ulauncher.io/";
        After = ["tray.target" "graphical-session.target"];
        Requires = ["tray.target"];
      };
    };
  };
}
