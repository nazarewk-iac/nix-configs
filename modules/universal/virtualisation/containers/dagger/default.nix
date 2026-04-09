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

  config = kdnConfig.util.ifTypes [ "nixos" ] (
    lib.mkIf cfg.enable {
      environment.systemPackages = with pkgs; [
        cue
        dagger
        cuelsp
      ];
    }
  );
}
