{
  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}:
let
  cfg = config.kdn.development.llm.omp;
in
{
  options.kdn.development.llm.omp = {
    enable = lib.mkEnableOption "OhMyPi (omp) coding agent CLI harness";
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      (kdnConfig.util.ifHMParent {
        home-manager.sharedModules = [ { kdn.development.llm.omp = lib.mkDefault cfg; } ];
      })
      (kdnConfig.util.ifHM {
        kdn.apps.omp = {
          enable = true;
          # pkgs.omp comes from the can1357/oh-my-pi flake overlay.
          package.original = pkgs.omp;
          # omp keeps config and sessions in ~/.omp.
          dirs.data = [ "/.omp" ];
        };
      })
    ]
  );
}
