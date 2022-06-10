{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.nazarewk.development.rust;
in
{
  options.nazarewk.development.rust = {
    enable = mkEnableOption "Rust development";
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      rustc
      cargo
      rustfmt
    ];
  };
}
