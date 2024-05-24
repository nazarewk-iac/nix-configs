{ lib, pkgs, config, ... }:
let
  cfg = config.kdn.development.python;

  defaultPython = pkgs.python312;

  mkPython = pkg: (pkg.withPackages (ps: with ps; [
    pip-tools
    black
    boto3
    build # build a package, see https://realpython.com/pypi-publish-python-package/#build-your-package
    cookiecutter
    diagrams
    flake8
    graphviz
    httpx
    httpie
    ipython
    isort
    matplotlib
    mt-940
    pendulum
    pip
    pipx
    pyaml
    pyheos
    pytest
    pyyaml
    requests
    ruamel-yaml
    tqdm
    twine # upload to pypi, see https://realpython.com/pypi-publish-python-package/#upload-your-package

    pycrypto

    (pkgs.http-prompt.override { python3Packages = ps; httpie = ps.httpie; })
  ]));

  renamedBinariesOnly = fmt: pkg: pkgs.runCommand "${pkg.name}-renamed-to-${builtins.replaceStrings [ "%s" ] [ "BIN" ] fmt}"
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
  '';

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

    environment.systemPackages = with pkgs; [
      # python software not available in `python.withPackages`
      pipenv
      poetry

      (http-prompt.override (let pp = defaultPython.pkgs; in { python3Packages = pp; httpie = pp.httpie; }))
      (mkPython defaultPython)
      # full packages contain tkinter https://github.com/NixOS/nixpkgs/blob/7f5639fa3b68054ca0b062866dc62b22c3f11505/pkgs/top-level/all-packages.nix#L16633-L16634
      (renamedBinariesOnly "%s.3.9" python39)
      (renamedBinariesOnly "%s.3.10" python310)
      (renamedBinariesOnly "%s.3.11" python311)
      (renamedBinariesOnly "%s.3.12" python312)

      graphviz
    ];
  };
}
