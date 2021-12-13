{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.programs.nix-direnv;
in {
  options.programs.nix-direnv = {
    enable = mkEnableOption "nix-direnv";
  };

  config = mkIf cfg.enable {

    programs.zsh.interactiveShellInit = ''
      eval "$(${pkgs.direnv}/bin/direnv hook zsh)"
    '';

    programs.bash.interactiveShellInit = ''
      eval "$(${pkgs.direnv}/bin/direnv hook bash)"
    '';

    environment.systemPackages = with pkgs; [ direnv nix-direnv ];
    # nix options for derivations to persist garbage collection
    nix.extraOptions = ''
      keep-outputs = true
      keep-derivations = true
    '';
    environment.pathsToLink = [
      "/share/nix-direnv"
    ];
    # if you also want support for flakes (this makes nix-direnv use the
    # unstable version of nix):
    nixpkgs.overlays = [
      (self: super: { nix-direnv = super.nix-direnv.override { enableFlakes = true; }; } )
    ];

    home-manager.sharedModules = [
      {
        xdg.configFile."direnv/lib/nix-direnv.sh".text = ''
        source "/run/current-system/sw/share/nix-direnv/direnvrc"
        '';
        programs.git.ignores = [ (builtins.readFile ./.gitignore) ];
      }
    ];
  };
}