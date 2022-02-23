{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.nazarewk.development.elixir;
in {
  options.nazarewk.development.elixir = {
    enable = mkEnableOption "elixir development";
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      elixir
    ];
  };
}