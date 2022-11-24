{ pkgs, ... }:
let
  lib = pkgs.lib;

  attrs = {
    python = pkgs."python311";
    projectDir = ./.;
    pyproject = ./pyproject.toml;
    poetrylock = ./poetry.lock;
    overrides = pkgs.poetry2nix.defaultPoetryOverrides.extend (final: prev: (builtins.listToAttrs [
      #fido2 = prev.fido2.overridePythonAttrs (old: { buildInputs = (old.buildInputs or [ ]) ++ [ final.poetry ]; });
    ]) // { });
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
