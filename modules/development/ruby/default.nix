{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.nazarewk.development.ruby;
in
{
  options.nazarewk.development.ruby = {
    enable = mkEnableOption "Ruby development";
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      ruby_3_0
    ];
  };
}
