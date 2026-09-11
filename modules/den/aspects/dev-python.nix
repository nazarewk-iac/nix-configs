# The `development/python` module of the old tree, as a den aspect.
#
# The old module stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# It installs one Python 3.13 with a large package set under the plain binary names, plus six more
# interpreters whose binaries carry a version suffix. A `meta.priority` value per entry settles every
# file conflict. On Home Manager it also adds the Python language servers to Helix and it appends the
# Python ignore rules to the global git ignore file.
#
# ## What the port changes
#
# 1. **`enable` goes.** Inclusion is the switch.
# 2. **`kdn.env.packages` goes.** Each target writes the native package option of its own class,
#    through ../common/filter-packages.nix. Design B.
# 3. **The Matplotlib override becomes a per-class constant.** The old module asks
#    `kdnConfig.util.isOfType [ "nixos" ]` at build time. An aspect has no such argument, and it does
#    not need one: the class already states the answer. The NixOS target turns on the GTK 3 and the
#    Qt backend; the Darwin target and the Home Manager target take the plain package. This holds the
#    old behaviour on a NixOS host. A Home Manager user on a NixOS host now gets the plain package,
#    where the old tree gave the GTK 3 build — the old module ran in the host context for the same
#    machine.
# 4. **The ignore file gets a name without a leading dot.** The old file is `.gitignore`, next to the
#    old module. A `.gitignore` inside the den tree would act as a real ignore file, so the copy is
#    `./dev-python/gitignore`.
# 5. **The forward to Home Manager goes.** den needs no forward: a consumer names the class it
#    wants.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch.
# 3. **No custom module argument.** Each target module below takes `lib` and `pkgs` only.
{ ... }:
let
  # `nixos` turns on the two graphical backends of Matplotlib. Every other class takes the plain
  # package.
  packages =
    {
      lib,
      pkgs,
      graphicalMatplotlib,
    }:
    let
      defaultPython = pkgs.python313;

      mkMatplotlib =
        prev:
        if !graphicalMatplotlib then
          prev
        else
          prev.override {
            enableGtk3 = true;
            enableQt = true;
          };

      mkPython =
        pkg:
        (pkg.withPackages (
          ps:
          with ps;
          [
            beautifulsoup4
            black
            boto3
            # It builds a package. See
            # https://realpython.com/pypi-publish-python-package/#build-your-package
            build
            cookiecutter
            deepmerge
            diagrams
            duckdb
            fire
            flake8
            fsspec
            graphviz
            h2
            httpie
            httpx
            ipython
            isort
            keyring
            (mkMatplotlib matplotlib)
            mt-940
            pendulum
            pip
            pip-tools
            # pipx # TODO: 2026-05-28: the build is broken. See nixpkgs issue 522307.
            pyaml
            pyheos
            pytest
            pyyaml
            regex
            requests
            ruamel-yaml
            tqdm
            # It uploads to PyPI. See
            # https://realpython.com/pypi-publish-python-package/#upload-your-package
            twine
            types-beautifulsoup4
            universal-pathlib

            pycrypto
          ]
          ++ [
            xdg-base-dirs
          ]
          ++ [
            # the log tools
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
    import ../common/filter-packages.nix { inherit lib; } (
      with pkgs;
      [
        # the Python software that `python.withPackages` does not carry
        pipenv
        #poetry # TODO: 2024-04-07 it did not build

        # Note: a higher `prio` value means a lower priority at install time.
        (lib.meta.setPrio 1 (mkPython defaultPython))
        (lib.meta.setPrio 17 (renamedBinariesOnly "%s.3.14-ft" python314FreeThreading))
        (lib.meta.setPrio 17 (renamedBinariesOnly "%s.3.14" python314))
        (lib.meta.setPrio 18 (renamedBinariesOnly "%s.3.13-ft" python313FreeThreading))
        (lib.meta.setPrio 19 (renamedBinariesOnly "%s.3.13" python313))
        (lib.meta.setPrio 20 (renamedBinariesOnly "%s.3.12" python312))
        (lib.meta.setPrio 21 (renamedBinariesOnly "%s.3.11" python311))

        graphviz
      ]
    );
in
{
  kdn.dev-python.nixos =
    { lib, pkgs, ... }:
    {
      environment.systemPackages = packages {
        inherit lib pkgs;
        graphicalMatplotlib = true;
      };
    };

  kdn.dev-python.darwin =
    { lib, pkgs, ... }:
    {
      environment.systemPackages = packages {
        inherit lib pkgs;
        graphicalMatplotlib = false;
      };
    };

  kdn.dev-python.homeManager =
    { lib, pkgs, ... }:
    {
      home.packages = packages {
        inherit lib pkgs;
        graphicalMatplotlib = false;
      };

      programs.git.ignores = [ (builtins.readFile ./dev-python/gitignore) ];

      programs.helix.extraPackages = with pkgs; [
        ty
        ruff
        # https://github.com/python-lsp/python-lsp-server
        (python3.withPackages (
          pp: with pp; [
            jedi # it completes a name
            jedi-language-server
            python-lsp-server

            # the dependencies and the optional plugins
            mccabe
            # the formatters: yapf over autopep8
            autopep8
            yapf
            # the primary linters: pyflakes over flake8 and autopep8
            flake8
            pyflakes
            pylint
            # the linters
            pycodestyle
            pydocstyle
            # the third-party plugins
            pylsp-mypy
            pylsp-rope
            python-lsp-black
            (python-lsp-ruff.overridePythonAttrs (old: {
              # TODO: it does not build. See nixpkgs issue 548631.
              doCheck = false;
            }))
            pyls-isort
            pyls-memestra
          ]
        ))
      ];
    };
}
