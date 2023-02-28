{ lib, pkgs, config, ... }:
let
  cfg = config.kdn.programs.ydotool;
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
    systemd.packages = [ cfg.package ];
    environment.systemPackages = [
      cfg.package
    ];
  };
}
