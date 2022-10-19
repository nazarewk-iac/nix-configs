{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.kdn.development.elixir;
in
{
  options.kdn.development.elixir = {
    enable = lib.mkEnableOption "elixir development";
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      elixir
    ];
  };
}
