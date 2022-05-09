{ lib, pkgs, config, flakeInputs, system, ... }:
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
      (self: super: let
        tvPkgs = import flakeInputs.nixpkgs-teamviewer { system = system; config = { allowUnfree = true; }; };
      in {
        teamviewer = tvPkgs.teamviewer;
      })
    ];
  };
}
