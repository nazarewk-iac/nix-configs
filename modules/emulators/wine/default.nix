{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.kdn.emulators.windows;
in
{
  options.kdn.emulators.windows = {
    enable = lib.mkEnableOption "WINE windows executables runner";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      winetricks
      (if config.kdn.sway.base.enable then wineWowPackages.waylandFull else wineWowPackages.stagingFull)
    ];
  };
}
