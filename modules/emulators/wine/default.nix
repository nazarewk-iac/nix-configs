{ lib, pkgs, config, ... }:
let
cfg = config.kdn.emulators.wine;
in
{
options.kdn.emulators.wine = {
enable = lib.mkEnableOption "WINE windows executables runner";
};

config = lib.mkIf cfg.enable {
environment.systemPackages = with pkgs; [
winetricks
(if config.kdn.sway.base.enable then wineWowPackages.waylandFull else wineWowPackages.stagingFull)
];
};
}
