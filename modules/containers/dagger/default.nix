{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.kdn.containers.dagger;
in
{
  options.kdn.containers.dagger = {
    enable = lib.mkEnableOption "Dagger.io development setup";
  };

  config = lib.mkIf cfg.enable {
    kdn.containers.podman.enable = lib.mkDefault true;
    kdn.containers.docker.enable = lib.mkDefault false;

    environment.systemPackages = with pkgs; [
      cue
      dagger
      cuelsp
    ];
  };
}
