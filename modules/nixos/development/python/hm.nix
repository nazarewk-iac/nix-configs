{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.development.python;
in {
  options.kdn.development.python = {
    enable = lib.mkEnableOption "Python development";
  };

  config = lib.mkIf cfg.enable {
    programs.helix.extraPackages = with pkgs; [
      ty
      ruff
      (python3.withPackages (
        pp:
          with pp; [
            # https://github.com/python-lsp/python-lsp-server
            # python-lsp-server # TODO: failed to build on 2025-12-19
            # dependencies/optional plugins
            mccabe
            # formatters: yapf > autopep8
            autopep8
            yapf
            # primary linters: pyflakes > flake8/autopep8
            flake8
            pyflakes
            pylint
            # linters
            pycodestyle
            pydocstyle

            # 3rd party plugins
            pylsp-mypy
            pylsp-rope
            python-lsp-black
            python-lsp-ruff
            pyls-isort
            pyls-memestra
          ]
      ))
    ];
  };
}
