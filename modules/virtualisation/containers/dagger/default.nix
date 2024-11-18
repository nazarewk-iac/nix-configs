{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.virtualisation.containers.dagger;
in {
  options.kdn.virtualisation.containers.dagger = {
    enable = lib.mkEnableOption "Dagger.io development setup";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      cue
      dagger
      cuelsp
    ];
  };
}
