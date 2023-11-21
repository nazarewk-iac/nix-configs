{ lib, pkgs, config, inputs, ... }:
let
  cfg = config.kdn.programs.ulauncher;
in
{
  options.kdn.programs.ulauncher = {
    enable = lib.mkEnableOption "ulauncher";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.ulauncher6;
    };

  };

  config = lib.mkIf cfg.enable {
    home.file.".local/share/dbus-1/services/io.ulauncher.Ulauncher.service".source = "${cfg.package}/share/dbus-1/services/io.ulauncher.Ulauncher.service";
    home.packages = [ cfg.package ];
  };
}
