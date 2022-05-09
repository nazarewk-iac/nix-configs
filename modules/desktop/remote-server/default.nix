{ lib, pkgs, config, flakeInputs, ... }:
with lib;
let
  cfg = config.nazarewk.desktop.remote-server;
in {
  options.nazarewk.desktop.remote-server = {
    enable = mkEnableOption "remote desktop server setup";
  };

  config = mkIf cfg.enable {
    services.teamviewer.enable = true;
    nixpkgs.overlays = [
      (self: super: {
        teamviewer = flakeInputs.nixpkgs-teamviewer.legacyPackages.x86_64-linux.teamviewer;
      })
    ];
  };
}
