{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.development.rpi;
in {
  options.kdn.development.rpi = {
    enable = lib.mkEnableOption "rpi development/debugging";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      rpi-imager
    ];
  };
}
