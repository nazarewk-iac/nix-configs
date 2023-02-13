{ lib, pkgs, config, ... }:
let
  cfg = config.kdn.programs.direnv;
in
{
  options.kdn.programs.direnv = {
    enable = lib.mkEnableOption "nix-direnv setup";
  };

  config = lib.mkIf cfg.enable {
    # nix options for derivations to persist garbage collection
    nix.extraOptions = ''
      keep-outputs = true
      keep-derivations = true
    '';
    ## if you also want support for flakes (this makes nix-direnv use the
    ## unstable version of nix):
    #nixpkgs.overlays = [
    #  (final: prev: { nix-direnv = prev.nix-direnv.override { enableFlakes = true; }; })
    #];

    home-manager.sharedModules = [{
      home.packages = with pkgs; [ direnv nix-direnv ];
      programs.direnv.enable = true;
      programs.direnv.nix-direnv.enable = true;
      programs.git.ignores = [ (builtins.readFile ./.gitignore) ];
    }];
  };
}
