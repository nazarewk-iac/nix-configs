{
  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}:
let
  cfg = config.kdn.development.llm.pi;
in
{
  options.kdn.development.llm.pi = {
    enable = lib.mkEnableOption "Pi coding agent CLI harness";
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      (kdnConfig.util.ifHMParent {
        home-manager.sharedModules = [ { kdn.development.llm.pi = lib.mkDefault cfg; } ];
      })
      (kdnConfig.util.ifHM {
        kdn.apps.pi = {
          enable = true;
          # nixpkgs names the package pi-coding-agent; the binary is `pi`.
          package.original = pkgs.pi-coding-agent;
          # pi keeps config and sessions in ~/.pi (no XDG support yet).
          dirs.data = [ "/.pi" ];
        };
      })
    ]
  );
}
