{ lib, pkgs, config, ... }:
let
  cfg = config.kdn.programs.fish;
in
{
  options.kdn.programs.fish = {
    enable = lib.mkEnableOption "fish interactive shell";
  };

  config = lib.mkIf cfg.enable {
    programs.fish = {
      enable = true;
      useBabelfish = false;
    };
    home-manager.sharedModules = [{
      home.packages = with pkgs; [
        grc
        fzf
        babelfish
      ];
      programs.fish = {
        enable = true;
        interactiveShellInit = ''
          set fish_greeting # Disable greeting
        '';
        plugins = with pkgs.fishPlugins; [
          { name = "grc"; src = grc.src; }
          { name = "done"; src = done.src; }
          { name = "forgit"; src = forgit.src; }
          #{ name = "hydro"; src = hydro.src; }
          { name = "fzf"; src = fzf-fish.src; }
        ];
      };
    }];
  };
}