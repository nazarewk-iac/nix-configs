{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.kdn.programs.ydotool;

  sock = "/run/ydotool.sock";
in
{
  options.kdn.programs.ydotool = {
    enable = lib.mkEnableOption "command-line automation tool";
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.ydotool;
      defaultText = lib.literalExpression "pkgs.ydotool";
    };
  };

  config = lib.mkIf cfg.enable {
    hardware.uinput.enable = true;

    systemd.packages = [ cfg.package ];
    environment.systemPackages = [
      cfg.package
    ];

    users.groups.ydotool.gid = 26598;
    environment.variables.YDOTOOL_SOCKET = sock;

    systemd.services."ydotoold" = {
      description = "/dev/uinput automation tool";
      wantedBy = [ "default.target" ];
      serviceConfig = {
        ExecStart = "${pkgs.ydotool}/bin/ydotoold --socket-perm=0660 --socket-own=0:${toString config.users.groups.ydotool.gid} --socket-path=${sock}";
        ExecReload = "/usr/bin/kill -HUP $MAINPID";
        KillMode = "process";
      };
    };
  };
}
