{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.nazarewk.sway.remote;
in {
  options.nazarewk.sway.remote = {
    enable = mkEnableOption "remote access setup for Sway";
  };

  config = mkIf cfg.enable {
    nazarewk.sway.base.enable = true;

    environment.systemPackages = with pkgs; [
      wayvnc
      waypipe

      remmina
      # didn't build on 2022-04-25
      #tigervnc
    ];
  };
}
