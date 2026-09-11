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
    kdn.env.packages =
      (with pkgs; [
        cue
        cuelsp
      ])
      # nixpkgs holds no `dagger` attribute, so a bare `dagger` aborts the evaluation. Take the
      # package only when an overlay or a flake input supplies it.
      ++ lib.optional (pkgs ? dagger) pkgs.dagger;
  };
}
