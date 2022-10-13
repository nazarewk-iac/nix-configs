{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.kdn.development.elixir;
in
{
  options.kdn.development.elixir = {
    enable = mkEnableOption "elixir development";
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      elixir
    ];
  };
}
