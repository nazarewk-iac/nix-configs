{ pkgs, ... }:
let
  lib = pkgs.lib;

  attrs = {
    python = pkgs."python311";
    projectDir = ./.;
    pyproject = ./pyproject.toml;
    poetrylock = ./poetry.lock;
    overrides = pkgs.poetry2nix.defaultPoetryOverrides.extend (final: prev: {
      fido2 = prev.fido2.overridePythonAttrs (old: { buildInputs = (old.buildInputs or [ ]) ++ [ final.poetry ]; });
      yubikey-manager = prev.yubikey-manager.overridePythonAttrs (old: { buildInputs = (old.buildInputs or [ ]) ++ [ final.poetry ]; });

      cryptography = prev.cryptography.overridePythonAttrs (old:
        {
          cargoDeps =
            pkgs.rustPlatform.fetchCargoTarball {
              src = old.src;
              sourceRoot = "${old.pname}-${old.version}/${old.cargoRoot}";
              name = "${old.pname}-${old.version}";
              sha256 = "sha256-lzHLW1N4hZj+nn08NZiPVM/X+SEcIsuZDjEOy0OOkSc=";
            };
        });

      pyscard = prev.pyscard.overridePythonAttrs (old:
        # see https://github.com/nazarewk/nixpkgs/blob/013fcdd106823416918004bb684c3c186d3c460f/pkgs/development/python-modules/pyscard/default.nix
        let
          withApplePCSC = stdenv.isDarwin;
          PCSC = pkgs.PCSC;
          pcsclite = pkgs.pcsclite;
          stdenv = pkgs.stdenv;
        in
        {
          postPatch =
            if withApplePCSC then ''
              substituteInPlace smartcard/scard/winscarddll.c \
                --replace "/System/Library/Frameworks/PCSC.framework/PCSC" \
                          "${PCSC}/Library/Frameworks/PCSC.framework/PCSC"
            '' else ''
              substituteInPlace smartcard/scard/winscarddll.c \
                --replace "libpcsclite.so.1" \
                          "${lib.getLib pcsclite}/lib/libpcsclite${stdenv.hostPlatform.extensions.sharedLibrary}"
            '';
          propagatedBuildInputs = (old.propagatedBuildInputs or [ ]) ++ (
            if withApplePCSC then [ PCSC ] else [ pcsclite ]
          );
          NIX_CFLAGS_COMPILE = lib.optionalString (! withApplePCSC)
            "-I ${lib.getDev pcsclite}/include/PCSC";
          nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [
            pkgs.swig
          ];
        }
      );
    });
  };

  cfg = builtins.fromTOML (builtins.readFile attrs.pyproject);
  name = cfg.tool.poetry.name;
  pkg = pkgs.poetry2nix.mkPoetryApplication (attrs // { });
  env = pkgs.poetry2nix.mkPoetryEnv (attrs // {
    editablePackageSources = { "${name}" = attrs.projectDir; };
  });
in
{
  inherit pkg env cfg;
  bin = "${pkg}/bin/${name}";
}
