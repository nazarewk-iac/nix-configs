{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.nazarewk.development.python;
in {
  options.nazarewk.development.python = {
    enable = mkEnableOption "Python development";
  };

  config = mkIf cfg.enable {
    home-manager.sharedModules = [
      {
        programs.git.ignores = [ (builtins.readFile ./.gitignore) ];
      }
    ];
    environment.systemPackages = with pkgs; [
      # python software
      pipenv
      poetry
      black
      (python310.withPackages (ps: with ps; [
        boto3
        cookiecutter
        flake8
        ipython
        pip
        pip-tools
        pipx
        pyaml
        pytest
        pyyaml
        requests
        graphviz
      ]))

      graphviz
    ];

    environment.localBinInPath = true;
  };
}