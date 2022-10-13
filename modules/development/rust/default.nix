{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.kdn.development.rust;
in
{
  options.kdn.development.rust = {
    enable = mkEnableOption "Rust development";
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      rustup
      pkg-config
    ];
  };
}
