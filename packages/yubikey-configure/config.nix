{ pkgs, ... }:
let
  attrs = {
    python = pkgs."python311";
    projectDir = ./.;
    pyproject = ./pyproject.toml;
    poetrylock = ./poetry.lock;
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
