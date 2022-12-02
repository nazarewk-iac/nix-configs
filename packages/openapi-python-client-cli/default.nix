{ pkgs, ... }:
pkgs.poetry2nix.mkPoetryApplication {
  python = pkgs.python311;
  projectDir = ./.;
  overrides = pkgs.poetry2nix.defaultPoetryOverrides.extend (final: prev: {
    autoflake = prev.autoflake.overridePythonAttrs (old: { buildInputs = (old.buildInputs or [ ]) ++ (with final; [ hatchling ]); });
    openapi-python-client = prev.openapi-python-client.overridePythonAttrs (old: { buildInputs = (old.buildInputs or [ ]) ++ (with final; [ poetry-core ]); });
  });
}
