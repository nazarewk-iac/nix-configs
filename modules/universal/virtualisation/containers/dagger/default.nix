{

  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}:
let
  cfg = config.kdn.virtualisation.containers.dagger;
in
{
  options.kdn.virtualisation.containers.dagger = {
    enable = lib.mkEnableOption "Dagger.io development setup";
  };

  config = lib.mkIf cfg.enable {
    kdn.env.packages = with pkgs; [
      cue
      dagger
      cuelsp
    ];
  };
}
