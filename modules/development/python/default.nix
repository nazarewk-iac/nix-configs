{ lib, pkgs, config, ... }:
let
  cfg = config.kdn.development.python;

  defaultPython = pkgs.python312;

  mkPython = pkg: (pkg.withPackages (ps: with ps; [
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
    requests
    ruamel-yaml
    tqdm
    twine # upload to pypi, see https://realpython.com/pypi-publish-python-package/#upload-your-package
    types-beautifulsoup4
    universal-pathlib

    pycrypto

    (pkgs.http-prompt.override { python3Packages = ps; httpie = ps.httpie; })
  ]));

  renamedBinariesOnly = fmt: pkg: (pkgs.runCommand "${pkg.name}-renamed-to-${builtins.replaceStrings [ "%s" ] [ "BIN" ] fmt}"
    { buildInputs = [ ]; } ''
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
  '');

in
{
  options.kdn.development.python = {
    enable = lib.mkEnableOption "Python development";
  };

  config = lib.mkIf cfg.enable {
    home-manager.sharedModules = [
      { kdn.development.python.enable = true; }
      { programs.git.ignores = [ (builtins.readFile ./.gitignore) ]; }
    ];
    nixpkgs.overlays = [
      (final: prev: {
        matplotlib = prev.matplotlib.override {
          enableGtk3 = true;
          enableQt = true;
        };
      })
    ];

    environment.systemPackages = (with pkgs; [
      # python software not available in `python.withPackages`
      pipenv
      poetry

      # Note: higher `prio` value means lower prioritity during install
      (lib.meta.setPrio 1 (mkPython defaultPython))
      (lib.meta.setPrio 19 (renamedBinariesOnly "%s.3.13" python313))
      (lib.meta.setPrio 20 (renamedBinariesOnly "%s.3.12" python312))
      (lib.meta.setPrio 21 (renamedBinariesOnly "%s.3.11" python311))
      (lib.meta.setPrio 22 (renamedBinariesOnly "%s.3.10" python310))
      (lib.meta.setPrio 23 (renamedBinariesOnly "%s.3.9" python39))

      graphviz
    ]);
  };
}
