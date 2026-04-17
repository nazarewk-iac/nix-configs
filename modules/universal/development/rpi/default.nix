{

  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}:
let
  cfg = config.kdn.development.rpi;
in
{
  options.kdn.development.rpi = {
    enable = lib.mkEnableOption "rpi development/debugging";
  };

  config = lib.mkIf cfg.enable {
    kdn.env.packages = with pkgs; [
      #rpi-imager # TODO: 2025-10-28: broken https://github.com/NixOS/nixpkgs/issues/454826
    ];
  };
}
