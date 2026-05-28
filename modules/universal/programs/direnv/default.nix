{

  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}:
let
  cfg = config.kdn.programs.direnv;
in
{
  options.kdn.programs.direnv = {
    enable = lib.mkEnableOption "nix-direnv setup";
  };

  config = lib.mkMerge [
    (kdnConfig.util.ifHMParent {
      home-manager.sharedModules = [ { kdn.programs.direnv = cfg; } ];
    })
    (kdnConfig.util.ifTypes [ "nixos" ] (
      lib.mkIf cfg.enable {
        # nix options for derivations to persist garbage collection in devenv
        nix.extraOptions = ''
          keep-outputs = true
          keep-derivations = true
        '';
        ## if you also want support for flakes (this makes nix-direnv use the
        ## unstable version of nix):
        #nixpkgs.overlays = [
        #  (final: prev: { nix-direnv = prev.nix-direnv.override { enableFlakes = true; }; })
        #];
      }
    ))
    (kdnConfig.util.ifHM (
      lib.mkIf cfg.enable {
        home.packages = with pkgs; [
          direnv
          nix-direnv
        ];
        programs.direnv.enable = true;
        programs.direnv.nix-direnv.enable = true;
        programs.git.ignores = [ (builtins.readFile ./.gitignore) ];
        kdn.disks.persist."usr/data".directories = [ ".local/share/direnv" ];
        kdn.disks.persist."usr/config".directories = [ ".config/direnv" ];
      }
    ))
  ];
}
