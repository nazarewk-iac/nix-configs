{
  pkgs,
  lib,
  extraRuntimeDeps ? [],
  sops,
  age,
  watchexec,
  ...
}: let
  pythonDeps = with pkgs.python3Packages; [
    fire
    xdg-base-dirs
    structlog
  ];
  runtimeDeps =
    [
      watchexec
      sops
      age
    ]
    ++ extraRuntimeDeps;
in
  pkgs.writers.writePython3Bin "kdn-secrets"
  {
    libraries = pythonDeps;
    makeWrapperArgs = builtins.concatLists [
      ["--prefix" "PATH" ":" (lib.makeBinPath runtimeDeps)]
    ];
    flakeIgnore = [
      "E501" # line too long
    ];
  }
  (builtins.readFile ./kdn-secrets.py)
