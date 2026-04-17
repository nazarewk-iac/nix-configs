{

  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}:
let
  cfg = config.kdn.development.elixir;
in
{
  options.kdn.development.elixir = {
    enable = lib.mkEnableOption "elixir development";
  };

  config = lib.mkIf cfg.enable {
    kdn.env.packages = with pkgs; [
      elixir
    ];
  };
}
