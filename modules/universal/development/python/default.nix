{

  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}:
let
  cfg = config.kdn.development.python;

  defaultPython = pkgs.python313;

  mkPython =
    pkg:
    (pkg.withPackages (
      ps:
      with ps;
      [
        beautifulsoup4
        black
        boto3
        build # build a package, see https://realpython.com/pypi-publish-python-package/#build-your-package
        cookiecutter
        deepmerge
        diagrams
        duckdb
        fire
        flake8
        fsspec
        graphviz
        httpie
        httpx
        ipython
        isort
        keyring
        matplotlib
        mt-940
        pendulum
        pip
        pip-tools
        pipx
        pyaml
        pyheos
        pytest
        pyyaml
        regex
        requests
        ruamel-yaml
        tqdm
        twine # upload to pypi, see https://realpython.com/pypi-publish-python-package/#upload-your-package
        types-beautifulsoup4
        universal-pathlib

        pycrypto
      ]
      ++ [
        xdg-base-dirs
      ]
      ++ [
        # logging
        rich
        structlog
      ]
    ));

  renamedBinariesOnly =
    fmt: pkg:
    (pkgs.runCommand "${pkg.name}-renamed-to-${builtins.replaceStrings [ "%s" ] [ "BIN" ] fmt}"
      { buildInputs = [ ]; }
      ''
        set -x
        ${lib.toShellVar "srcDir" "${pkg}/bin"}
        ${lib.toShellVar "fmt" fmt}

        mkdir -p "$out/bin"
        if test "$fmt" = "%s" ; then
          echo "fmt $fmt must modify filename!"
          exit 1
        fi

        for file in "$srcDir"/* ; do
          if test -e "$(printf "$fmt" "$file")" || ! test -x "$file" ; then
            continue
          fi
          filename="''${file##*/}"
          renamed="$(printf "$fmt" "$filename")"
          ln -sfT "$file" "$out/bin/$renamed"
        done
        set +x
      ''
    );
in
{
  options.kdn.development.python = {
    enable = lib.mkEnableOption "Python development";
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        kdn.env.packages = with pkgs; [
          # python software not available in `python.withPackages`
          pipenv
          #poetry # TODO: 2024-04-07 didn't build

          # Note: higher `prio` value means lower prioritity during install
          (lib.meta.setPrio 1 (mkPython defaultPython))
          (lib.meta.setPrio 17 (renamedBinariesOnly "%s.3.14-ft" python314FreeThreading))
          (lib.meta.setPrio 17 (renamedBinariesOnly "%s.3.14" python314))
          (lib.meta.setPrio 18 (renamedBinariesOnly "%s.3.13-ft" python313FreeThreading))
          (lib.meta.setPrio 19 (renamedBinariesOnly "%s.3.13" python313))
          (lib.meta.setPrio 20 (renamedBinariesOnly "%s.3.12" python312))
          (lib.meta.setPrio 21 (renamedBinariesOnly "%s.3.11" python311))

          graphviz
        ];
      }
      (kdnConfig.util.ifHM {
        programs.helix.extraPackages = with pkgs; [
          ty
          ruff
          # https://github.com/python-lsp/python-lsp-server
          # python-lsp-server # TODO: failed to build on 2025-12-19
          (python3.withPackages (
            pp: with pp; [
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
      })
      (kdnConfig.util.ifHMParent {
        home-manager.sharedModules = [
          { kdn.development.python.enable = true; }
        ];
      })
      (kdnConfig.util.ifHM {
        programs.git.ignores = [ (builtins.readFile ./.gitignore) ];
      })
      (kdnConfig.util.ifTypes [ "nixos" ] {
        nixpkgs.overlays = [
          (final: prev: {
            matplotlib = prev.matplotlib.override {
              enableGtk3 = true;
              enableQt = true;
            };
          })
        ];
      })
    ]
  );
}
