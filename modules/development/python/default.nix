{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.kdn.development.python;

  mkPython = pkg: (pkg.withPackages (ps: with ps; [
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
      test -x "$file" || continue
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
      (renamedBinariesOnly "%s3.8" python38)
      (renamedBinariesOnly "%s3.9" python39)
      (mkPython python310)
      (renamedBinariesOnly "%s3.10" (mkPython python310))
      (renamedBinariesOnly "%s3.11" python311)

      graphviz

      kdn.openapi-python-client-cli
    ];
  };
}
