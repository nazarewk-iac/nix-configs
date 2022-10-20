{ pkgs, ... }:
pkgs.poetry2nix.mkPoetryApplication {
  projectDir = ./.;

  # see https://github.com/nix-community/poetry2nix/blob/5aa37b8a5652a4c2a2372e82815ebd15db07f087/docs/edgecases.md?plain=1#L137-L149
  overrides = pkgs.poetry2nix.defaultPoetryOverrides.extend (final: prev: {
    keyring-pass = prev.keyring-pass.overridePythonAttrs (
      old: {
        buildInputs = (old.buildInputs or [ ]) ++ [ final.poetry ];
      }
    );
  });
}
