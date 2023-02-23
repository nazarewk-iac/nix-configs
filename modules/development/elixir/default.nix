{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.kdn.development.elixir;
in
{
  options.kdn.development.elixir = {
    enable = lib.mkEnableOption "elixir development";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      elixir
    ];
  };
}
