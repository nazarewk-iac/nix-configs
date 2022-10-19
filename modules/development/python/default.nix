{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.kdn.development.python;
in
{
  options.kdn.development.python = {
    enable = lib.mkEnableOption "Python development";
  };

  config = mkIf cfg.enable {
    home-manager.sharedModules = [
      {
        programs.git.ignores = [ (builtins.readFile ./.gitignore) ];
      }
    ];
    nixpkgs.overlays = [
      (final: prev: {
        matplotlib = prev.matplotlib.override {
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
        build # build a package, see https://realpython.com/pypi-publish-python-package/#build-your-package
        cookiecutter
        diagrams
        flake8
        graphviz
        ipython
        isort
        matplotlib
        pip
        # pip-tools  # 2022-08-31 fails on `assert out.exit_code == 2` @ test_bad_setup_file()
        pipx
        pyaml
        pyheos
        pytest
        pyyaml
        requests
        ruamel-yaml
        twine # upload to pypi, see https://realpython.com/pypi-publish-python-package/#upload-your-package
      ]))

      graphviz
    ];

    environment.localBinInPath = true;
  };
}
