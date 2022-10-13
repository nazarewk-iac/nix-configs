{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.kdn.development.ruby;
in
{
  options.kdn.development.ruby = {
    enable = mkEnableOption "Ruby development";
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      ruby_3_0
    ];
  };
}
