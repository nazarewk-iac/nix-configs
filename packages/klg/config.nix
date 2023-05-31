{ pkgs, ... }@args:
let
  inherit (pkgs) lib;

  klog = pkgs.callPackage ../klog-time-tracker { };

  attrs = {
    python = pkgs.python311;
    projectDir = ./.;
    pyproject = ./pyproject.toml;
    poetrylock = ./poetry.lock;
    buildInputs = [
      klog
    ];
    groups = [ ];
    overrides = pkgs.poetry2nix.overrides.withDefaults (final: prev: {
      # async-cache = prev.async-cache.overridePythonAttrs (old: {
      #   buildInputs = (old.buildInputs or [ ]) ++ (with final; [ setuptools ]);
      # });
    });
  };

  cfg = builtins.fromTOML (builtins.readFile attrs.pyproject);
  name = cfg.tool.poetry.name;
  pkg = pkgs.poetry2nix.mkPoetryApplication (attrs // { });
  env = pkgs.poetry2nix.mkPoetryEnv (attrs // {
    groups = [ "dev" "test" ];
    editablePackageSources = { "${name}" = attrs.projectDir; };
  });
in
{
  inherit pkg env cfg klog;
  inherit (attrs) python;
  bin = "${pkg}/bin/${name}";
}
