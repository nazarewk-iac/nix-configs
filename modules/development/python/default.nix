{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.nazarewk.development.python;
in
{
  options.nazarewk.development.python = {
    enable = mkEnableOption "Python development";
  };

  config = mkIf cfg.enable {
    home-manager.sharedModules = [
      {
        programs.git.ignores = [ (builtins.readFile ./.gitignore) ];
      }
    ];
    nixpkgs.overlays = [
      (self: super: {
        matplotlib = super.matplotlib.override {
          enableGtk3 = true;
          enableQt = true;
        };
      })
    ];
    environment.systemPackages = with pkgs; [
      # python software
      pipenv
      poetry
      (python310.withPackages (ps: with ps; [
        black
        boto3
        cookiecutter
        diagrams
        flake8
        graphviz
        ipython
        matplotlib
        pip
        pip-tools
        pipx
        pyaml
        pyheos
        pytest
        pyyaml
        requests
      ]))

      graphviz
    ];

    environment.localBinInPath = true;
  };
}
