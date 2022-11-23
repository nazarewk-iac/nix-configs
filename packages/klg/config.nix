{ pkgs, ... }:
let
  lib = pkgs.lib;

  attrs = {
    python = pkgs."python311";
    projectDir = ./.;
    pyproject = ./pyproject.toml;
    poetrylock = ./poetry.lock;
    overrides = pkgs.poetry2nix.defaultPoetryOverrides.extend (final: prev:
      let
        addPackages = name: packages: {
          name = name;
          value = prev."${name}".overridePythonAttrs (old: {
            buildInputs = (old.buildInputs or [ ]) ++ packages;
          });
        };
      in
      (builtins.listToAttrs [
        (addPackages "justpy" (with final; [ flit-core ]))
        (addPackages "starlette" (with final; [ hatchling ]))
        (addPackages "structlog" (with final; [ hatchling hatch-fancy-pypi-readme hatch-vcs ]))
        (addPackages "nicegui" (with final; [ poetry ]))
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
