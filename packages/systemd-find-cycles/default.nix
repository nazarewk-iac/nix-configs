{
  pkgs,
  lib,
  ...
}: let
  local = ./systemd-find-cycles.py;

  python = pkgs.python3.withPackages (pp:
    with pp; [
      decorator
      graphviz
      networkx
      pydot
      pyparsing
    ]);

  writer = pkgs.writers.makeScriptWriter {
    interpreter = python.interpreter;
    makeWrapperArgs = builtins.concatLists [
      ["--prefix" "PATH" ":" "${pkgs.systemd}/bin"]
    ];
  };

  script = writer "/bin/systemd-find-cycles" local // {inherit python;};
in
  script
